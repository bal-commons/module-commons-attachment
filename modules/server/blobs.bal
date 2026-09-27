import ballerina/file;
import ballerina/io;
import ballerina/sql;
import ballerinax/java.jdbc;
import commons/service_commons.db as sdb;

// Where file content lives. A transactional store joins the database transaction of the upload.
type BlobStore isolated object {
    isolated function isTransactional() returns boolean;
    isolated function put(string id, byte[] content) returns error?;
    isolated function get(string id) returns byte[]|error;
    isolated function remove(string id) returns error?;
};

isolated class DatabaseBlobs {
    *BlobStore;
    private final jdbc:Client db;
    private final string blobTable;

    isolated function init(jdbc:Client db, string prefix) {
        self.db = db;
        self.blobTable = prefix + "blob";
    }

    isolated function isTransactional() returns boolean => true;

    isolated function put(string id, byte[] content) returns error? {
        _ = check self.db->execute(sql:queryConcat(`INSERT INTO `, sdb:ident(self.blobTable),
            ` (file_id, content) VALUES (${id}, ${content})`));
    }

    isolated function get(string id) returns byte[]|error {
        record {|byte[] content;|} row = check self.db->queryRow(sql:queryConcat(`SELECT content FROM `,
            sdb:ident(self.blobTable), ` WHERE file_id = ${id}`));
        return row.content;
    }

    isolated function remove(string id) returns error? {
        _ = check self.db->execute(sql:queryConcat(`DELETE FROM `, sdb:ident(self.blobTable),
            ` WHERE file_id = ${id}`));
    }
}

// One file per attachment under `<dir>/<ns>/`; IDs are ULIDs, so they are safe file names.
isolated class FileBlobs {
    *BlobStore;
    private final string dir;

    isolated function init(string root, string ns) returns error? {
        self.dir = check file:joinPath(root, ns);
        check file:createDir(self.dir, file:RECURSIVE);
    }

    isolated function isTransactional() returns boolean => false;

    isolated function put(string id, byte[] content) returns error? {
        check io:fileWriteBytes(check file:joinPath(self.dir, id), content);
    }

    isolated function get(string id) returns byte[]|error {
        return io:fileReadBytes(check file:joinPath(self.dir, id));
    }

    isolated function remove(string id) returns error? {
        string path = check file:joinPath(self.dir, id);
        if check file:test(path, file:EXISTS) {
            check file:remove(path);
        }
    }
}
