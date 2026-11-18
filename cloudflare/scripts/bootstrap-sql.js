export function ownerBootstrapSql({
  id,
  name,
  username,
  passwordHash,
  createdAt,
}) {
  const quote = (value) => "'" + value.replaceAll("'", "''") + "'";
  // One SQL statement is atomic in D1; an existing owner is never overwritten.
  return (
    "INSERT INTO users(id,name,username,password_hash,role,active,created_at) SELECT " +
    [id, name, username, passwordHash, "owner"].map(quote).join(",") +
    ",1," +
    quote(createdAt) +
    " WHERE NOT EXISTS(SELECT 1 FROM users WHERE role='owner');\n"
  );
}
