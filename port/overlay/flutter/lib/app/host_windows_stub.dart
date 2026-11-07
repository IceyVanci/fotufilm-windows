// Browsers and mobile have no Windows host.
bool openUrl(String url) => false;
bool openFile(String path) => false;
void reveal(List<String> paths) {}
List<String> trash(List<String> paths) => const [];
