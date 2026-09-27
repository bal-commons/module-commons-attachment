import commons/service_commons.db as sdb;

final sdb:Migration[] & readonly migrations = [
    {
        version: 1,
        description: "cases, subjects, slots and files",
        statements: schema("BLOB"),
        dialectStatements: {[sdb:MYSQL]: schema("LONGBLOB"), [sdb:POSTGRESQL]: schema("BYTEA")}
    }
];

isolated function schema(string blobType) returns string[] & readonly => [
    string `CREATE TABLE {prefix}case (
        id VARCHAR(26) NOT NULL PRIMARY KEY,
        ns VARCHAR(64) NOT NULL,
        idempotency_key VARCHAR(255),
        correlation_id VARCHAR(255) NOT NULL,
        title VARCHAR(500) NOT NULL,
        description TEXT,
        status VARCHAR(16) NOT NULL,
        watchers VARCHAR(2000) NOT NULL,
        auto_submit INT NOT NULL,
        created_by VARCHAR(255) NOT NULL,
        created_at BIGINT NOT NULL,
        updated_at BIGINT NOT NULL,
        due_at BIGINT,
        submitted_at BIGINT,
        submitted_by VARCHAR(255),
        closed_at BIGINT,
        closed_by VARCHAR(255),
        status_reason VARCHAR(1000),
        metadata TEXT)`,
    "CREATE UNIQUE INDEX {prefix}case_idempotency ON {prefix}case (ns, idempotency_key)",
    "CREATE INDEX {prefix}case_correlation ON {prefix}case (ns, correlation_id)",
    string `CREATE TABLE {prefix}subject (
        case_id VARCHAR(26) NOT NULL,
        user_id VARCHAR(255) NOT NULL,
        PRIMARY KEY (case_id, user_id))`,
    "CREATE INDEX {prefix}subject_user ON {prefix}subject (user_id, case_id)",
    string `CREATE TABLE {prefix}slot (
        case_id VARCHAR(26) NOT NULL,
        name VARCHAR(64) NOT NULL,
        slot_order INT NOT NULL,
        label VARCHAR(255) NOT NULL,
        description VARCHAR(2000),
        mime_types VARCHAR(1000) NOT NULL,
        max_bytes BIGINT NOT NULL,
        min_files INT NOT NULL,
        max_files INT NOT NULL,
        file_count INT NOT NULL,
        PRIMARY KEY (case_id, name))`,
    string `CREATE TABLE {prefix}file (
        id VARCHAR(26) NOT NULL PRIMARY KEY,
        case_id VARCHAR(26) NOT NULL,
        slot VARCHAR(64) NOT NULL,
        file_name VARCHAR(255) NOT NULL,
        mime_type VARCHAR(255) NOT NULL,
        size_bytes BIGINT NOT NULL,
        sha256 VARCHAR(64) NOT NULL,
        uploaded_by VARCHAR(255) NOT NULL,
        uploaded_at BIGINT NOT NULL)`,
    "CREATE INDEX {prefix}file_case ON {prefix}file (case_id, id)",
    string `CREATE TABLE {prefix}blob (
        file_id VARCHAR(26) NOT NULL PRIMARY KEY,
        content ${blobType} NOT NULL)`
];
