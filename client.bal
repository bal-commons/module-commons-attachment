import ballerina/http;
import ballerina/url;

# Client for the attachment service.
public isolated client class Client {
    private final http:Client http;
    private final map<string> & readonly headers;

    # Creates a client.
    #
    # + serviceUrl - Base URL including the base path, e.g. `http://localhost:9102/attachments/v1`
    # + config - HTTP client settings, including `auth` for OAuth2 client credentials
    # + headers - Sent on every request, e.g. `x-api-key`, or `x-user-id` in trusted-header mode
    # + return - An error if the client cannot be created
    public isolated function init(string serviceUrl, http:ClientConfiguration config = {}, map<string> headers = {})
            returns error? {
        self.http = check new (serviceUrl, config);
        self.headers = headers.cloneReadOnly();
    }

    # Creates a case. Requires the case-create scope.
    #
    # + newCase - The case
    # + return - The case (the original one when `idempotencyKey` repeats), or an error
    remote isolated function createCase(NewCase newCase) returns Case|error {
        return self.http->post("/cases", newCase, self.headers);
    }

    # Gets a case with its files.
    #
    # + caseId - Case ID
    # + return - The case, or an error (404 when the caller may not read it)
    remote isolated function getCase(string caseId) returns Case|error {
        return self.http->get(check casePath(caseId), self.headers);
    }

    # Lists the cases the caller is asked to upload to, newest first.
    #
    # + options - Filters and paging
    # + return - One page, or an error
    remote isolated function listCases(*CaseListOptions options) returns CasePage|error {
        return self.http->get("/cases" + check queryString(options), self.headers);
    }

    # Lists any cases. Requires the admin scope or an admin role with `read`.
    #
    # + options - Filters and paging
    # + return - One page, or an error
    remote isolated function adminListCases(*AdminCaseListOptions options) returns CasePage|error {
        return self.http->get("/admin/cases" + check queryString(options), self.headers);
    }

    # Uploads a file to a slot.
    #
    # + caseId - Case ID
    # + slot - Slot name
    # + fileName - File name
    # + content - File content
    # + contentType - Media type
    # + return - The stored file, or an error
    remote isolated function upload(string caseId, string slot, string fileName, byte[] content, string contentType)
            returns Attachment|error {
        http:Request req = new;
        req.setBinaryPayload(content, contentType);
        return self.http->post(string `${check casePath(caseId)}/slots/${check encode(slot)}/files?fileName=${
            check encode(fileName)}`, req, self.headers);
    }

    # Lists a case's files.
    #
    # + caseId - Case ID
    # + return - The files, or an error
    remote isolated function listFiles(string caseId) returns Attachment[]|error {
        return self.http->get(check casePath(caseId) + "/files", self.headers);
    }

    # Downloads a file.
    #
    # + caseId - Case ID
    # + fileId - File ID
    # + return - The content, or an error
    remote isolated function download(string caseId, string fileId) returns byte[]|error {
        http:Response response = check self.http->get(check filePath(caseId, fileId) + "/content", self.headers);
        if response.statusCode != http:STATUS_OK {
            return error(string `Download failed with status ${response.statusCode}`);
        }
        return response.getBinaryPayload();
    }

    # Creates a short-lived download link that needs no credentials.
    #
    # + caseId - Case ID
    # + fileId - File ID
    # + return - The link, or an error
    remote isolated function createLink(string caseId, string fileId) returns AttachmentLink|error {
        return self.http->post(check filePath(caseId, fileId) + "/link", (), self.headers);
    }

    # Deletes a file: its uploader while the case is open, or an admin role with `delete`.
    #
    # + caseId - Case ID
    # + fileId - File ID
    # + return - An error if it does not exist or the call fails
    remote isolated function deleteFile(string caseId, string fileId) returns error? {
        http:Response response = check self.http->delete(check filePath(caseId, fileId), (), self.headers);
        return expectStatus(response, http:STATUS_NO_CONTENT);
    }

    # Submits a case once every slot is satisfied. Subjects only.
    #
    # + caseId - Case ID
    # + return - The submitted case, or an error (409 when a slot still needs files)
    remote isolated function submit(string caseId) returns Case|error {
        return self.http->post(check casePath(caseId) + "/submit", (), self.headers);
    }

    # Reopens a submitted case for more uploads.
    #
    # + caseId - Case ID
    # + reason - Shown to the subjects
    # + return - The case, or an error
    remote isolated function reopen(string caseId, string? reason = ()) returns Case|error {
        return self.http->post(check casePath(caseId) + "/reopen", statusChange(reason), self.headers);
    }

    # Closes a case; no more uploads are accepted.
    #
    # + caseId - Case ID
    # + reason - Why it is closed
    # + return - The case, or an error
    remote isolated function close(string caseId, string? reason = ()) returns Case|error {
        return self.http->post(check casePath(caseId) + "/close", statusChange(reason), self.headers);
    }

    # Registers a webhook for a participant. Requires the webhook scope.
    #
    # + webhook - The webhook
    # + return - The webhook with its secret, or an error
    remote isolated function registerWebhook(NewWebhook webhook) returns CreatedWebhook|error {
        return self.http->post("/webhooks", webhook, self.headers);
    }

    # Lists webhooks. Requires the webhook scope.
    #
    # + participantId - Only this participant's
    # + return - The webhooks, or an error
    remote isolated function listWebhooks(string? participantId = ()) returns Webhook[]|error {
        return self.http->get("/webhooks" + check queryString({"participantId": participantId}), self.headers);
    }

    # Lists a webhook's recent deliveries. Requires the webhook scope.
    #
    # + webhookId - Webhook ID
    # + return - Deliveries, newest first, or an error
    remote isolated function webhookDeliveries(string webhookId) returns WebhookDelivery[]|error {
        return self.http->get(string `/webhooks/${check encode(webhookId)}/deliveries`, self.headers);
    }

    # Removes a webhook. Requires the webhook scope.
    #
    # + webhookId - Webhook ID
    # + return - An error if it does not exist or the call fails
    remote isolated function removeWebhook(string webhookId) returns error? {
        http:Response response = check self.http->delete(string `/webhooks/${check encode(webhookId)}`, (),
            self.headers);
        return expectStatus(response, http:STATUS_NO_CONTENT);
    }

    # Issues a single-use ticket for opening the SSE stream from a browser.
    #
    # + return - The ticket, or an error
    remote isolated function streamTicket() returns StreamTicket|error {
        return self.http->post("/stream-ticket", (), self.headers);
    }

    # Opens the caller's SSE stream.
    #
    # + return - The event stream, or an error
    remote isolated function events() returns stream<http:SseEvent, error?>|error {
        return self.http->get("/stream", self.headers);
    }
}

isolated function statusChange(string? reason) returns StatusChange => reason is string ? {reason} : {};

isolated function encode(string value) returns string|error => url:encode(value, "UTF-8");

isolated function casePath(string caseId) returns string|error => string `/cases/${check encode(caseId)}`;

isolated function filePath(string caseId, string fileId) returns string|error =>
    string `${check casePath(caseId)}/files/${check encode(fileId)}`;

isolated function expectStatus(http:Response response, int expected) returns error? {
    if response.statusCode != expected {
        return error(string `Request failed with status ${response.statusCode}: ${check response.getTextPayload()}`);
    }
}

isolated function queryString(record {} params) returns string|error {
    string[] parts = [];
    foreach [string, anydata] [key, value] in params.entries() {
        if value !is () {
            parts.push(string `${key}=${check encode(value.toString())}`);
        }
    }
    return parts.length() == 0 ? "" : "?" + string:'join("&", ...parts);
}
