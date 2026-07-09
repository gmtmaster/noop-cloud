import http from "node:http";
import { createApp } from "./app.js";
import { createPostgresStore } from "./postgres.js";

const port = Number(process.env.PORT ?? 8787);
const db = createPostgresStore();
const app = createApp({
  db,
  tokenHashPepper: process.env.TOKEN_HASH_PEPPER ?? ""
});

const server = http.createServer(app);

server.listen(port, () => {
  console.log(`Noop Cloud Sync backend listening on :${port}`);
});

async function shutdown() {
  server.close(async () => {
    await db.close();
    process.exit(0);
  });
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
