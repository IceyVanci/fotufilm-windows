import Foundation
#if canImport(Android)
// Foundation carries math.h onto Android but not the POSIX headers this file is written against.
import Android
#endif
#if os(Windows)
// The mapping is a file mapping object: CreateFileW, SetEndOfFile, CreateFileMappingW,
// MapViewOfFile, and the file's own write path for `write`.
import WinSDK
#endif

/// A buffer that a large render can hold for its whole duration without spending the process's
/// memory allowance on it. iOS kills an app for the *dirty* pages it holds, not for the address
/// space it has mapped.
public final class MappedBuffer: @unchecked Sendable {
    public enum StoragePreference: Sendable {
        /// Large buffers use temporary files to limit resident memory.
        case automatic
        /// Keep a buffer in memory only within the caller's explicit allowance.
        /// Larger buffers retain automatic storage; allocation failure may use a file.
        case memory(upTo: Int)
        /// Limits anonymous memory for this allocation. Sizes above the cap must use a
        /// temporary file or fail; they never fall back to anonymous memory. A zero or
        /// negative cap requires file backing even below `mappingThreshold`.
        /// Sizes at or below the cap try memory first and may fall back to a file.
        /// This does not limit aggregate allocations or the residency of mapped pages.
        case boundedMemory(upTo: Int)
    }

    /// Above this, a buffer is worth putting on disk.
    public static let mappingThreshold = 32 << 20

    /// The descriptor or handle a mapped buffer keeps for `write`: a POSIX descriptor on the
    /// Unix platforms, the file HANDLE on Windows.
    #if os(Windows)
    typealias Backing = UnsafeMutableRawPointer
    #else
    typealias Backing = Int32
    #endif

    public let byteCount: Int
    /// False when this fell back to — or never left — anonymous memory.
    public let isMapped: Bool
    /// The allowance reserved by this allocation, including an explicit memory preference.
    public var residentByteCount: Int { isMapped ? 0 : byteCount }
    public let baseAddress: UnsafeMutableRawPointer
    #if os(Windows)
    /// The file behind the mapping, kept open for `write` and `flush`; nil when not mapped.
    private let backing: Backing?
    #else
    /// The backing file, kept open for `write`; -1 when not mapped.
    private let descriptor: Backing
    #endif

    /// Allocates `byteCount` bytes using the requested per-allocation storage policy.
    public convenience init?(byteCount: Int, storage: StoragePreference = .automatic) {
        self.init(byteCount: byteCount, storage: storage, allocation: .system)
    }

    /// Per-call resource factories keep allocation-failure tests independent of process globals.
    /// Successful factories must retain the standard malloc/free and mmap/munmap ownership.
    struct Allocation {
        var memory: (Int) -> UnsafeMutableRawPointer?
        var file: (Int) -> (UnsafeMutableRawPointer, Backing)?

        static var system: Self {
            Self(memory: { malloc($0) }, file: MappedBuffer.map)
        }
    }

    init?(byteCount: Int, storage: StoragePreference, allocation: Allocation) {
        guard byteCount > 0 else { return nil }
        self.byteCount = byteCount
        let prefersMemory: Bool
        let requiresMapping: Bool
        switch storage {
        case .automatic:
            prefersMemory = false; requiresMapping = false
        case .memory(let limit):
            prefersMemory = byteCount <= limit; requiresMapping = false
        case .boundedMemory(let limit):
            prefersMemory = byteCount <= max(0, limit)
            requiresMapping = !prefersMemory
        }
        if requiresMapping || (!prefersMemory && byteCount >= Self.mappingThreshold) {
            if let (mapped, backing) = allocation.file(byteCount) {
                baseAddress = mapped
                #if os(Windows)
                self.backing = backing
                #else
                descriptor = backing
                #endif
                isMapped = true
                return
            }
            guard !requiresMapping else { return nil }
        }
        guard let memory = allocation.memory(byteCount) else {
            guard prefersMemory, let (mapped, backing) = allocation.file(byteCount) else { return nil }
            baseAddress = mapped
            #if os(Windows)
            self.backing = backing
            #else
            descriptor = backing
            #endif
            isMapped = true
            return
        }
        memory.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
        baseAddress = memory
        #if os(Windows)
        backing = nil
        #else
        descriptor = -1
        #endif
        isMapped = false
    }

    deinit {
        #if os(Windows)
        if isMapped {
            _ = UnmapViewOfFile(baseAddress)
            if let backing { _ = CloseHandle(backing) }
        } else {
            free(baseAddress)
        }
        #else
        if isMapped {
            #if !os(WASI)
            munmap(baseAddress, byteCount)
            close(descriptor)
            #endif
        } else {
            free(baseAddress)
        }
        #endif
    }

    /// Maps a temporary file, or nil if any step of it fails.
    private static func map(byteCount: Int) -> (UnsafeMutableRawPointer, Backing)? {
        #if os(WASI)
        // WebAssembly linear memory cannot map files. Policies that require mapping fail;
        // other policies retain their existing allocator fallback above.
        return nil
        #elseif os(Windows)
        // A temporary file the system deletes when its last handle closes: the mapping holds
        // that handle, so the file goes away with the buffer.
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("fotufilm-\(UUID().uuidString)")
        let widePath = Array(path.utf16) + [0]
        let file = widePath.withUnsafeBufferPointer { buffer -> HANDLE? in
            guard let base = buffer.baseAddress else { return nil }
            return CreateFileW(base, DWORD(GENERIC_READ) | DWORD(GENERIC_WRITE),
                               DWORD(FILE_SHARE_READ) | DWORD(FILE_SHARE_WRITE)
                                   | DWORD(FILE_SHARE_DELETE),
                               nil, DWORD(CREATE_NEW),
                               DWORD(FILE_ATTRIBUTE_TEMPORARY) | DWORD(FILE_FLAG_DELETE_ON_CLOSE),
                               nil)
        }
        guard let file, file != UnsafeMutableRawPointer(bitPattern: -1) else { return nil }
        var length = LARGE_INTEGER()
        length.QuadPart = Int64(byteCount)
        guard SetFilePointerEx(file, length, nil, DWORD(FILE_BEGIN)), SetEndOfFile(file) else {
            _ = CloseHandle(file)
            return nil
        }
        let section = CreateFileMappingW(file, nil, DWORD(PAGE_READWRITE),
                                         DWORD(truncatingIfNeeded: byteCount >> 32),
                                         DWORD(truncatingIfNeeded: byteCount), nil)
        guard let section else {
            _ = CloseHandle(file)
            return nil
        }
        // The view keeps the section alive, so the section's handle is no longer needed.
        let view = MapViewOfFile(section, DWORD(FILE_MAP_READ) | DWORD(FILE_MAP_WRITE), 0, 0, 0)
        _ = CloseHandle(section)
        guard let view else {
            _ = CloseHandle(file)
            return nil
        }
        return (view, file)
        #else
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("fotufilm-\(UUID().uuidString)")
        let descriptor = open(path, O_RDWR | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { return nil }
        unlink(path)
        guard ftruncate(descriptor, off_t(byteCount)) == 0 else {
            close(descriptor)
            return nil
        }
        let mapped = mmap(nil, byteCount, PROT_READ | PROT_WRITE,
                          MAP_SHARED, descriptor, 0)
        // `MAP_FAILED` is `((void *)-1)`, a cast Swift does not import as a constant on every
        // platform, and `mmap` comes back optional on some of them and not on others. The failure
        // it reports is the same one either way.
        guard let mapped = mapped as UnsafeMutableRawPointer?,
              Int(bitPattern: mapped) != -1 else {
            close(descriptor)
            return nil
        }
        return (mapped, descriptor)
        #endif
    }

    /// Stores `count` bytes at `byteOffset` through the file rather than the mapping. Writing a
    /// large mapping dirties its pages faster than the kernel will write them back, and it
    /// answers by stalling the writer — an iPhone spent thirty seconds of a forty-second
    /// rasterise stopped that way — where the file's own write path streams them out. The
    /// mapping sees the bytes the same: it is the same page cache.
    public func write(from source: UnsafeRawPointer, byteOffset: Int, byteCount count: Int) {
        guard count > 0, byteOffset >= 0, byteOffset + count <= byteCount else { return }
        guard isMapped else {
            baseAddress.advanced(by: byteOffset).copyMemory(from: source, byteCount: count)
            return
        }
        #if os(Windows)
        // Windows' cache manager answers a mapped write the same way, so the file's own write
        // path carries the bytes and the view reads them back through the shared pages.
        guard let backing else { return }
        var position = LARGE_INTEGER()
        position.QuadPart = Int64(byteOffset)
        var written: DWORD = 0
        let wrote = SetFilePointerEx(backing, position, nil, DWORD(FILE_BEGIN))
            && WriteFile(backing, source, DWORD(truncatingIfNeeded: count), &written, nil)
        let taken = wrote ? Int(written) : 0
        if taken < count {
            // The mapping is still the truth of the buffer; what the file would not take goes
            // in through it.
            baseAddress.advanced(by: byteOffset + taken).copyMemory(
                from: source.advanced(by: taken), byteCount: count - taken)
        }
        #else
        var written = 0
        while written < count {
            let result = pwrite(descriptor, source.advanced(by: written), count - written,
                                off_t(byteOffset + written))
            if result <= 0 {
                if result < 0 && errno == EINTR { continue }
                // The mapping is still the truth of the buffer; what the file would not take
                // goes in through it.
                baseAddress.advanced(by: byteOffset + written).copyMemory(
                    from: source.advanced(by: written), byteCount: count - written)
                return
            }
            written += result
        }
        #endif
    }

    /// Asks the kernel to begin writing this range back.
    public func flush(byteOffset: Int, byteCount count: Int) {
        #if os(Windows)
        guard isMapped, count > 0, byteOffset >= 0,
              byteOffset + count <= byteCount else { return }
        _ = FlushViewOfFile(baseAddress.advanced(by: byteOffset), SIZE_T(count))
        #elseif !os(WASI)
        guard isMapped, count > 0, byteOffset >= 0,
              byteOffset + count <= byteCount else { return }
        let page = Int(getpagesize())
        let start = byteOffset - byteOffset % page
        msync(baseAddress.advanced(by: start), byteOffset - start + count,
              MS_ASYNC)
        #endif
    }

    /// The buffer as the one element type it holds.
    public func bound<T>(to type: T.Type) -> UnsafeMutableBufferPointer<T> {
        let count = byteCount / MemoryLayout<T>.stride
        return UnsafeMutableBufferPointer(
            start: baseAddress.bindMemory(to: type, capacity: count),
            count: count)
    }

    /// What automatic storage of this size reserves. Use `residentByteCount` for an allocation
    /// that supplies an explicit storage preference or may have fallen back to memory.
    public static func residentBytes(_ byteCount: Int) -> Int {
        #if os(WASI)
        return byteCount
        #else
        byteCount >= mappingThreshold ? 0 : byteCount
        #endif
    }
}