import ballerina/http;
import ballerina/log;
import ballerinax/java.jdbc;
import commons/attachment;
import commons/service_commons.auth as sauth;
import commons/service_commons.db as sdb;
import commons/service_commons.sse;
import commons/service_commons.webhook;

// Multipart framing and headers need room beyond the largest file.
listener http:Listener attachmentListener = new (port, requestLimits = {maxEntityBodySize: maxFileBytes + 1048576});

final jdbc:Client dbClient = check sdb:connect(db);
final webhook:Webhooks dispatcher = check new (dbClient, db.dbType, ns, tablePrefix + "webhook_", webhookDelivery);
final BlobStore blobs = storage == attachment:DATABASE ? new DatabaseBlobs(dbClient, tablePrefix)
    : check new FileBlobs(storageDir, ns);
final Store store = new (dbClient, ns, tablePrefix, blobs, dispatcher);
final sauth:Authenticator authenticator = check new (auth);
final sauth:TicketStore tickets = new (ticketTtlSeconds);
final sse:Hub hub = new;

function init() returns error? {
    check sdb:validatePrefix(tablePrefix);
    if db.initSchema {
        check sdb:migrate(dbClient, db.dbType, tablePrefix, migrations);
        check dispatcher.migrate();
    }
    foreach webhook:WebhookConfig configured in webhooks {
        _ = check dispatcher.upsert(configured);
    }
    check dispatcher.startRetries();
    check attachmentListener.attach(attachmentService, basePath);
    check attachmentListener.attach(linkService, basePath + "/links");
    log:printInfo(string `Attachment service on port ${port} at ${basePath} (ns ${ns}, ${db.dbType}, `
        + string `${storage} storage, ${adminRoles.length()} admin roles)`);
}
