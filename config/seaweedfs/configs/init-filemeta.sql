CREATE TABLE IF NOT EXISTS filemeta (
  dirhash BIGINT,
  name VARCHAR(65535),
  directory VARCHAR(65535),
  meta BYTEA,
  PRIMARY KEY (dirhash, name)
);

