import commons/attachment;
import commons/service_commons.auth as sauth;
import commons/service_commons.db as sdb;
import commons/service_commons.webhook;

# Port of the service's listener.
configurable int port = 9102;
# Base path the service is attached at; signed links are served under `<basePath>/links`.
configurable string basePath = "/attachments/v1";
# Namespace of every case this instance stores and serves.
configurable string ns = "default";
# Prefix of the service's tables; webhook tables use `<prefix>webhook_`.
configurable string tablePrefix = "attachment_";
# Listener auth.
configurable sauth:AuthConfig auth = {};
# Database connection.
configurable sdb:DbConfig db = {};
# Where file content is stored.
configurable attachment:StorageType storage = attachment:DATABASE;
# Directory for FILESYSTEM storage.
configurable string storageDir = "./attachments";
# Largest file any slot accepts, in bytes.
configurable int maxFileBytes = 10485760;
# Roles that may act on every case, and how.
configurable attachment:AdminRole[] adminRoles = [];
# Webhooks registered at startup, e.g. an agent's endpoint.
configurable webhook:WebhookConfig[] webhooks = [];
# Webhook delivery tuning.
configurable webhook:DispatcherConfig webhookDelivery = {};
# Scope required to create cases; users never hold it.
configurable string scopeCreate = "attachment:case:create";
# Scope that lets a service reopen and close any case.
configurable string scopeManage = "attachment:case:manage";
# Scope required to list, read, upload and submit as a subject.
configurable string scopeUse = "attachment:use";
# Scope that grants every operation on every case.
configurable string scopeAdmin = "attachment:admin";
# Scope required to manage webhooks.
configurable string scopeWebhooks = "attachment:webhook:manage";
# Key that signs download links; a random key is used when empty, so links end with the process.
configurable string linkSecret = "";
# Lifetime of a download link, in seconds.
configurable int linkTtlSeconds = 300;
# Largest page a listing returns.
configurable int maxPageSize = 100;
# Lifetime of an SSE stream ticket, in seconds.
configurable int ticketTtlSeconds = 60;
# Origins allowed by CORS.
configurable string[] corsAllowOrigins = ["*"];
