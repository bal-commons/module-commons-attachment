import ballerina/http;
import ballerina/lang.runtime;
import commons/attachment;
import commons/service_commons;
import commons/service_commons.webhook;

const URL = "http://localhost:19102/attachments/v1";
const AGENT = "agent:triage";
const USE = "attachment:use";

final byte[] & readonly PNG = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4];
final byte[] & readonly PDF = "%PDF-1.7 minimal".toBytes().cloneReadOnly();

isolated webhook:WebhookEvent[] agentInbox = [];

service /agent on new http:Listener(19303) {
    resource function post events(http:Request req) returns http:Accepted|http:Unauthorized {
        webhook:WebhookEvent|error event = webhook:verify(req, "s3cret");
        if event is error {
            return http:UNAUTHORIZED;
        }
        lock {
            agentInbox.push(event.clone());
        }
        return http:ACCEPTED;
    }
}

final attachment:Client workflow = check new (URL, headers = {
    "x-user-id": "maintenance-workflow", "x-user-scopes": "attachment:use attachment:case:create"
});

function persona(string userId, string roles = "", string scopes = USE) returns attachment:Client|error =>
    new (URL, headers = {"x-user-id": userId, "x-user-roles": roles, "x-user-scopes": scopes});

function statusOf(any|error result) returns int {
    if result is http:ApplicationResponseError {
        return result.detail().statusCode;
    }
    return result is error ? -1 : 200;
}

function photoCase(string subject, string correlationId, *record {|
            int maxFiles = 1;
            boolean autoSubmit = false;
            string[] watchers = [AGENT];
        |} options) returns attachment:Case|error {
    return workflow->createCase({
        correlationId,
        title: "Photos of the leak",
        subjects: [subject],
        watchers: options.watchers,
        autoSubmit: options.autoSubmit,
        slots: [
            {name: "leak-photo", label: "Photo of the leak", mimeTypes: ["image/*"], maxFiles: options.maxFiles},
            {name: "receipt", mimeTypes: ["application/pdf"], minFiles: 0}
        ]
    });
}

function agentReceives(string event, string correlationId) returns webhook:WebhookEvent|error {
    int deadline = service_commons:nowMillis() + 5000;
    while service_commons:nowMillis() < deadline {
        lock {
            foreach int i in 0 ..< agentInbox.length() {
                if agentInbox[i].event == event && agentInbox[i]?.correlationId == correlationId {
                    return agentInbox.remove(i).cloneReadOnly();
                }
            }
        }
        runtime:sleep(0.1);
    }
    return error(string `Agent did not receive ${event} for ${correlationId}`);
}

function nextOf(stream<http:SseEvent, error?> events, string name) returns json|error {
    int deadline = service_commons:nowMillis() + 10000;
    while service_commons:nowMillis() < deadline {
        record {|http:SseEvent value;|}? next = check events.next();
        if next is () {
            return error("stream ended");
        }
        if next.value.event == name {
            return (next.value.data ?: "null").fromJsonString();
        }
    }
    return error(string `No ${name} event`);
}
