import ballerina/crypto;
import ballerina/http;
import ballerina/uuid;
import commons/service_commons;

final string linkKey = linkSecret != "" ? linkSecret : uuid:createType4AsString() + uuid:createType4AsString();

isolated function signLink(string fileId, int expires) returns string|error {
    byte[] mac = check crypto:hmacSha256(string `${fileId}.${expires}`.toBytes(), linkKey.toBytes());
    return mac.toBase16();
}

isolated function linkFor(string fileId) returns [string, int]|error {
    int expires = service_commons:nowMillis() / 1000 + linkTtlSeconds;
    return [string `${basePath}/links/${fileId}?expires=${expires}&sig=${check signLink(fileId, expires)}`, expires];
}

// Serves signed links without credentials: the signature is the authorization.
final http:Service linkService = isolated service object {
    isolated resource function get [string fileId](int expires, string sig)
            returns http:Response|http:Forbidden|http:NotFound|error {
        if expires < service_commons:nowMillis() / 1000 || sig != check signLink(fileId, expires) {
            return service_commons:forbidden("The link is invalid or has expired");
        }
        [string, string]? file = check store.fileInfo(fileId);
        if file is () {
            return service_commons:notFound("File not found");
        }
        return contentResponse(check blobs.get(fileId), file[0], file[1], true);
    }
};

isolated function contentResponse(byte[] content, string fileName, string mimeType, boolean inline)
        returns http:Response {
    http:Response response = new;
    response.setBinaryPayload(content, mimeType);
    response.setHeader("Content-Disposition",
        string `${inline ? "inline" : "attachment"}; filename="${fileName}"`);
    response.setHeader("X-Content-Type-Options", "nosniff");
    response.setHeader("Cache-Control", "private, no-store");
    return response;
}
