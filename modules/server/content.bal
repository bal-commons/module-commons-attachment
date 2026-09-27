// Media type recognised from the first bytes of common upload formats.
isolated function sniff(byte[] b) returns string? {
    if startsWith(b, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
        return "image/png";
    }
    if startsWith(b, [0xFF, 0xD8, 0xFF]) {
        return "image/jpeg";
    }
    if startsWith(b, "GIF8".toBytes()) {
        return "image/gif";
    }
    if startsWith(b, "%PDF".toBytes()) {
        return "application/pdf";
    }
    if startsWith(b, "RIFF".toBytes()) && b.length() >= 12 && b.slice(8, 12) == "WEBP".toBytes() {
        return "image/webp";
    }
    return ();
}

isolated function startsWith(byte[] content, byte[] prefix) returns boolean =>
    content.length() >= prefix.length() && content.slice(0, prefix.length()) == prefix;

isolated function normalizeMime(string contentType) returns string {
    string mime = re `;`.split(contentType)[0].trim().toLowerAscii();
    return mime == "image/jpg" ? "image/jpeg" : mime;
}

isolated function accepts(string[] patterns, string mime) returns boolean {
    if patterns.length() == 0 {
        return true;
    }
    foreach string pattern in patterns {
        if pattern == mime || (pattern.endsWith("/*") && mime.startsWith(pattern.substring(0, pattern.length() - 1))) {
            return true;
        }
    }
    return false;
}

// Keeps the last path segment, drops control characters and quotes, and caps the length.
isolated function sanitizeFileName(string name) returns string {
    string[] segments = re `[/\\]`.split(name);
    string base = re `[\p{Cc}"]`.replaceAll(segments[segments.length() - 1], "").trim();
    if base == "" || base == "." || base == ".." {
        return "file";
    }
    return base.length() > 255 ? base.substring(base.length() - 255) : base;
}
