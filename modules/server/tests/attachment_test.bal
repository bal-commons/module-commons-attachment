import ballerina/crypto;
import ballerina/file;
import ballerina/http;
import ballerina/mime;
import ballerina/test;
import ballerinax/h2.driver as _;
import commons/attachment;
import commons/service_commons;
import commons/service_commons.webhook;

@test:Config
function onlyApplicationsCreateCases() returns error? {
    attachment:Client tara = check persona("tara");
    attachment:Case|error byUser = tara->createCase({title: "t", subjects: ["tara"], slots: [{name: "a"}]});
    test:assertEquals(statusOf(byUser), 403);

    attachment:Case|error noSlots = workflow->createCase({title: "t", subjects: ["tara"], slots: []});
    test:assertEquals(statusOf(noSlots), 400);
    attachment:Case|error badSlot = workflow->createCase({title: "t", subjects: ["tara"], slots: [{name: "a b"}]});
    test:assertEquals(statusOf(badSlot), 400);
    attachment:Case|error minOverMax = workflow->createCase({title: "t", subjects: ["tara"],
        slots: [{name: "a", minFiles: 2, maxFiles: 1}]});
    test:assertEquals(statusOf(minOverMax), 400);
    attachment:Case|error tooBig = workflow->createCase({title: "t", subjects: ["tara"],
        slots: [{name: "a", maxBytes: 999999}]});
    test:assertEquals(statusOf(tooBig), 400);
}

@test:Config
function idempotencyKeyMakesRetriesSafe() returns error? {
    attachment:NewCase request = {idempotencyKey: "wf-1/photos", correlationId: "wf-1", title: "Photos",
        subjects: ["ida"], slots: [{name: "photo"}]};
    attachment:Case first = check workflow->createCase(request);
    attachment:Case second = check workflow->createCase(request);
    test:assertEquals(second.id, first.id);
    test:assertEquals(first.watchers, ["maintenance-workflow"], "watchers default to the creator");
    test:assertEquals(first.slots[0].maxBytes, 4096, "slot size defaults to maxFileBytes");
}

@test:Config
function subjectUploadsAndEveryReaderDownloads() returns error? {
    attachment:Case created = check photoCase("tara", "case-up", maxFiles = 2);
    attachment:Client tara = check persona("tara");
    attachment:Attachment stored = check tara->upload(created.id, "leak-photo", "../../etc/leak.png", PNG,
        "image/png");
    test:assertEquals(stored.fileName, "leak.png", "paths are stripped from file names");
    test:assertEquals(stored.mimeType, "image/png");
    test:assertEquals(stored.sizeBytes, PNG.length());
    test:assertEquals(stored.sha256, crypto:hashSha256(PNG).toBase16());

    byte[] bySubject = check tara->download(created.id, stored.id);
    test:assertEquals(bySubject, PNG);
    byte[] byCreator = check workflow->download(created.id, stored.id);
    test:assertEquals(byCreator, PNG, "the creator reads its cases");
    attachment:Case withFiles = check tara->getCase(created.id);
    test:assertEquals((withFiles?.files ?: []).map(f => f.id), [stored.id]);
    test:assertEquals(withFiles.slots[0].fileCount, 1);
    test:assertTrue(withFiles.slots[0].satisfied);
    attachment:CasePage mine = check tara->listCases();
    test:assertTrue(mine.items.some(c => c.id == created.id));

    attachment:Client carlos = check persona("carlos");
    byte[]|error peek = carlos->download(created.id, stored.id);
    test:assertTrue(peek is error);
    attachment:Case|error hidden = carlos->getCase(created.id);
    test:assertEquals(statusOf(hidden), 404);
}

@test:Config
function uploadsAreCheckedAgainstTheSlot() returns error? {
    attachment:Case created = check photoCase("uma", "case-rules");
    attachment:Client uma = check persona("uma");
    attachment:Attachment|error pdfAsImage = uma->upload(created.id, "leak-photo", "a.pdf", PDF, "application/pdf");
    test:assertEquals(statusOf(pdfAsImage), 400);
    attachment:Attachment|error disguised = uma->upload(created.id, "leak-photo", "a.jpg", PDF, "image/jpeg");
    test:assertEquals(statusOf(disguised), 400, "the content is sniffed");
    byte[] large = [...PNG, ...(from int _ in 0 ..< 5000 select <byte>0)];
    attachment:Attachment|error tooLarge = uma->upload(created.id, "leak-photo", "big.png", large, "image/png");
    test:assertEquals(statusOf(tooLarge), 413);
    attachment:Attachment|error unknown = uma->upload(created.id, "roof", "a.png", PNG, "image/png");
    test:assertEquals(statusOf(unknown), 404);
    attachment:Attachment|error notSubject = workflow->upload(created.id, "leak-photo", "a.png", PNG, "image/png");
    test:assertEquals(statusOf(notSubject), 403);

    _ = check uma->upload(created.id, "leak-photo", "a.png", PNG, "application/octet-stream");
    attachment:Attachment|error full = uma->upload(created.id, "leak-photo", "b.png", PNG, "image/png");
    test:assertEquals(statusOf(full), 409);
    attachment:Attachment receipt = check uma->upload(created.id, "receipt", "r.pdf", PDF, "application/pdf");
    test:assertEquals(receipt.mimeType, "application/pdf");
}

@test:Config
function browserFormsUploadMultipart() returns error? {
    attachment:Case created = check photoCase("mia", "case-form");
    mime:Entity part = new;
    part.setContentDisposition(mime:getContentDispositionObject(
        "form-data; name=\"file\"; filename=\"kitchen.png\""));
    part.setByteArray(PNG, "image/png");
    http:Request req = new;
    req.setBodyParts([part], mime:MULTIPART_FORM_DATA);
    http:Client browser = check new (URL);
    http:Response response = check browser->post(string `/cases/${created.id}/slots/leak-photo/files`, req,
        {"x-user-id": "mia", "x-user-scopes": USE});
    test:assertEquals(response.statusCode, 201);
    json body = check response.getJsonPayload();
    test:assertEquals(check body.fileName, "kitchen.png");
}

@test:Config
function submitReopenAndCloseNotifyTheAgent() returns error? {
    attachment:Case created = check photoCase("sid", "case-flow");
    attachment:Client sid = check persona("sid");
    attachment:Case|error early = sid->submit(created.id);
    test:assertEquals(statusOf(early), 409, "the photo slot is not satisfied yet");

    attachment:Attachment photo = check sid->upload(created.id, "leak-photo", "p.png", PNG, "image/png");
    webhook:WebhookEvent uploaded = check agentReceives(attachment:EVENT_FILE_UPLOADED, "case-flow");
    json uploadData = uploaded.data;
    test:assertEquals(check uploadData.attachment.id, photo.id);

    attachment:Case submitted = check sid->submit(created.id);
    test:assertEquals(submitted.status, attachment:SUBMITTED);
    test:assertEquals(submitted?.submittedBy, "sid");
    webhook:WebhookEvent event = check agentReceives(attachment:EVENT_CASE_SUBMITTED, "case-flow");
    json submittedData = event.data;
    json[] files = check (check submittedData.'case.files).ensureType();
    test:assertEquals(files.length(), 1, "the agent gets the files with the submission");
    attachment:Attachment|error late = sid->upload(created.id, "receipt", "r.pdf", PDF, "application/pdf");
    test:assertEquals(statusOf(late), 409);

    attachment:Case|error byTenant = sid->reopen(created.id);
    test:assertEquals(statusOf(byTenant), 403);
    attachment:Case reopened = check workflow->reopen(created.id, "The photo is blurry, please upload another");
    test:assertEquals(reopened.status, attachment:OPEN);
    test:assertEquals(reopened?.statusReason, "The photo is blurry, please upload another");
    _ = check agentReceives(attachment:EVENT_CASE_REOPENED, "case-flow");

    attachment:Case closed = check workflow->close(created.id, "Resolved");
    test:assertEquals(closed.status, attachment:CLOSED);
    _ = check agentReceives(attachment:EVENT_CASE_CLOSED, "case-flow");
    attachment:Case|error again = workflow->reopen(created.id);
    test:assertEquals(statusOf(again), 409, "closed is final");
}

@test:Config
function autoSubmitCompletesTheCase() returns error? {
    attachment:Case created = check photoCase("amy", "case-auto", autoSubmit = true);
    attachment:Client amy = check persona("amy");
    _ = check amy->upload(created.id, "leak-photo", "p.png", PNG, "image/png");
    attachment:Case current = check amy->getCase(created.id);
    test:assertEquals(current.status, attachment:SUBMITTED);
    _ = check agentReceives(attachment:EVENT_CASE_SUBMITTED, "case-auto");
}

@test:Config
function adminRolesReadAndDeleteByPermission() returns error? {
    attachment:Case created = check photoCase("dan", "case-admin");
    attachment:Client dan = check persona("dan");
    attachment:Attachment photo = check dan->upload(created.id, "leak-photo", "p.png", PNG, "image/png");
    _ = check dan->submit(created.id);
    error? ownAfterSubmit = dan->deleteFile(created.id, photo.id);
    test:assertTrue(ownAfterSubmit is error && ownAfterSubmit.message().includes("status 409"),
        "uploaders delete only while the case is open");

    attachment:Client priya = check persona("priya", "PropertyManager");
    attachment:CasePage all = check priya->adminListCases(correlationId = "case-admin");
    test:assertEquals(all.items.map(c => c.id), [created.id]);
    byte[] byAdmin = check priya->download(created.id, photo.id);
    test:assertEquals(byAdmin, PNG);
    check priya->deleteFile(created.id, photo.id);
    attachment:Case after = check priya->getCase(created.id);
    test:assertEquals(after.slots[0].fileCount, 0);
    attachment:Case|error closeByPriya = priya->close(created.id);
    test:assertEquals(statusOf(closeByPriya), 403, "PropertyManager has no 'close'");

    attachment:Client auditor = check persona("audrey", "Auditor");
    attachment:CasePage|error listed = auditor->adminListCases();
    test:assertEquals(statusOf(listed), 403);
    attachment:Case|error hidden = auditor->getCase(created.id);
    test:assertEquals(statusOf(hidden), 404);
}

@test:Config
function uploaderDeletesWhileOpen() returns error? {
    attachment:Case created = check photoCase("ola", "case-del");
    attachment:Client ola = check persona("ola");
    attachment:Attachment photo = check ola->upload(created.id, "leak-photo", "p.png", PNG, "image/png");
    check ola->deleteFile(created.id, photo.id);
    attachment:Attachment replacement = check ola->upload(created.id, "leak-photo", "q.png", PNG, "image/png");
    test:assertNotEquals(replacement.id, photo.id);
    _ = check agentReceives(attachment:EVENT_FILE_DELETED, "case-del");
}

@test:Config
function signedLinksNeedNoCredentials() returns error? {
    attachment:Case created = check photoCase("lin", "case-link");
    attachment:Client lin = check persona("lin");
    attachment:Attachment photo = check lin->upload(created.id, "leak-photo", "p.png", PNG, "image/png");
    attachment:AttachmentLink link = check lin->createLink(created.id, photo.id);

    http:Client img = check new ("http://localhost:19102");
    http:Response ok = check img->get(link.url);
    test:assertEquals(ok.statusCode, 200);
    test:assertEquals(check ok.getBinaryPayload(), PNG);
    test:assertEquals(check ok.getHeader("Content-Type"), "image/png");

    http:Response tampered = check img->get(link.url.substring(0, link.url.length() - 2) + "00");
    test:assertEquals(tampered.statusCode, 403);
    int past = service_commons:nowMillis() / 1000 - 10;
    http:Response expired = check img->get(string `/attachments/v1/links/${photo.id}?expires=${past}&sig=${
        check signLink(photo.id, past)}`);
    test:assertEquals(expired.statusCode, 403);
}

@test:Config
function subjectsSeeNewCasesLive() returns error? {
    attachment:Client sam = check persona("sam");
    stream<http:SseEvent, error?> events = check sam->events();
    attachment:Case created = check photoCase("sam", "case-live");
    json event = check nextOf(events, attachment:EVENT_CASE_CREATED);
    test:assertEquals(check event.id, created.id);
    check events.close();
}

@test:Config
function webhooksAreManagedWithTheirScope() returns error? {
    attachment:Client ops = check persona("ops", scopes = "attachment:webhook:manage");
    attachment:Webhook[] configured = check ops->listWebhooks(AGENT);
    test:assertEquals(configured.length(), 1);
    attachment:Client user = check persona("ursula");
    attachment:Webhook[]|error denied = user->listWebhooks();
    test:assertEquals(statusOf(denied), 403);
}

@test:Config
function filesystemStoreKeepsContentOnDisk() returns error? {
    string dir = check file:createTempDir();
    FileBlobs blobs = check new (dir, "test");
    check blobs.put("01ABC", PNG);
    test:assertEquals(check blobs.get("01ABC"), PNG);
    check blobs.remove("01ABC");
    test:assertTrue(blobs.get("01ABC") is error);
    check blobs.remove("01ABC");
}

@test:Config
function contentHelpers() {
    test:assertEquals(sniff(PNG), "image/png");
    test:assertEquals(sniff(PDF), "application/pdf");
    test:assertEquals(sniff([0xFF, 0xD8, 0xFF, 0xE0]), "image/jpeg");
    test:assertEquals(sniff("hello".toBytes()), ());
    test:assertEquals(normalizeMime("Image/JPG; charset=x"), "image/jpeg");
    test:assertTrue(accepts(["image/*"], "image/webp"));
    test:assertFalse(accepts(["image/*"], "application/pdf"));
    test:assertTrue(accepts([], "anything/at-all"));
    test:assertEquals(sanitizeFileName("C:\\Users\\x\\photo \"1\".png"), "photo 1.png");
    test:assertEquals(sanitizeFileName(".."), "file");
}
