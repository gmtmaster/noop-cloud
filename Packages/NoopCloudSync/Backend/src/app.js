import { parseBearerToken, hashDeviceToken, makeSessionToken, makePasswordHash, verifyPassword } from "./token.js";

const MAX_BODY_BYTES = 10 * 1024 * 1024;

export function createApp({ db, tokenHashPepper = "" }) {
  if (!db) throw new Error("db is required");

  return async function handle(req, res) {
    try {
      const path = new URL(req.url, "http://localhost").pathname;

      if (req.method === "GET" && path === "/health") {
        return sendJSON(res, 200, { ok: true });
      }

      if (req.method === "POST" && path === "/v1/sync/batch") {
        return await handleSyncBatch(req, res, db, tokenHashPepper);
      }

      if (req.method === "POST" && path === "/v1/auth/signup") {
        return await handleAuthSignup(req, res, db, tokenHashPepper);
      }

      if (req.method === "POST" && path === "/v1/auth/login") {
        return await handleAuthLogin(req, res, db, tokenHashPepper);
      }

      if (req.method === "POST" && path === "/v1/auth/logout") {
        return await handleAuthLogout(req, res, db, tokenHashPepper);
      }

      if (req.method === "GET" && path === "/v1/friends/summary") {
        return await handleFriendsSummary(req, res, db, tokenHashPepper);
      }

      if (req.method === "POST" && path === "/v1/user/bootstrap") {
        return await handleUserBootstrap(req, res, db, tokenHashPepper);
      }

      if (req.method === "GET" && path === "/v1/user/me") {
        return await handleUserMe(req, res, db, tokenHashPepper);
      }

      if (req.method === "PATCH" && path === "/v1/user/me") {
        return await handleUserPatch(req, res, db, tokenHashPepper);
      }

      if (req.method === "PATCH" && path === "/v1/user/privacy") {
        return await handlePrivacyPatch(req, res, db, tokenHashPepper);
      }

      if (req.method === "POST" && path === "/v1/friends/request") {
        return await handleFriendRequest(req, res, db, tokenHashPepper);
      }

      if (req.method === "POST" && path === "/v1/friends/accept") {
        return await handleFriendshipAction(req, res, db, tokenHashPepper, "acceptFriendRequest");
      }

      if (req.method === "POST" && path === "/v1/friends/reject") {
        return await handleFriendshipAction(req, res, db, tokenHashPepper, "rejectFriendRequest");
      }

      if (req.method === "POST" && path === "/v1/friends/remove") {
        return await handleFriendshipAction(req, res, db, tokenHashPepper, "removeFriendship");
      }

      if (req.method === "GET" && path === "/v1/friends") {
        return await handleFriendsList(req, res, db, tokenHashPepper);
      }

      if (req.method === "GET" && path === "/v1/friends/requests") {
        return await handleFriendRequests(req, res, db, tokenHashPepper);
      }

      if (req.method === "GET" && path === "/v1/friends/feed") {
        return await handleFriendsFeed(req, res, db, tokenHashPepper);
      }

      return sendJSON(res, 404, { error: "not_found" });
    } catch (error) {
      if (error?.code === "username_conflict") return sendJSON(res, 409, { error: "username_conflict" });
      if (error?.code === "invalid_credentials") return sendJSON(res, 401, { error: "invalid_credentials" });
      if (error?.code === "user_not_bootstrapped") return sendJSON(res, 409, { error: "user_not_bootstrapped" });
      if (error?.code === "friendship_not_found") return sendJSON(res, 404, { error: "friendship_not_found" });
      if (error?.code === "friend_not_found") return sendJSON(res, 404, { error: "friend_not_found" });
      if (error?.code === "cannot_friend_self") return sendJSON(res, 400, { error: "cannot_friend_self" });
      console.error(error);
      return sendJSON(res, 500, { error: "internal_error" });
    }
  };
}

async function handleSyncBatch(req, res, db, tokenHashPepper) {
  const token = parseBearerToken(req.headers.authorization);
  if (!token) {
    return sendJSON(res, 401, { error: "missing_bearer_token" });
  }

  let batch;
  try {
    batch = JSON.parse(await readBody(req));
    validateBatch(batch);
  } catch (error) {
    return sendJSON(res, 400, { error: "invalid_batch", detail: error.message });
  }

  const deviceTokenHash = hashDeviceToken(token, tokenHashPepper);
  const result = await db.withTransaction(async (tx) => {
    const cloudDeviceId = await tx.findOrCreateCloudDevice(deviceTokenHash);
    const insertedBatch = await tx.insertSyncBatch(cloudDeviceId, batch);

    if (!insertedBatch) {
      return duplicateResult(batch);
    }

    const acceptedDailyMetrics = await tx.upsertDailyMetrics(cloudDeviceId, batch.dailyMetrics);
    const acceptedSleepSessions = await tx.upsertSleepSessions(cloudDeviceId, batch.sleepSessions);
    const acceptedWorkouts = await tx.upsertWorkouts(cloudDeviceId, batch.workouts);
    const acceptedMetricSeries = await tx.upsertMetricSeries(cloudDeviceId, batch.metricSeries);

    return {
      duplicate: false,
      acceptedDailyMetrics,
      acceptedSleepSessions,
      acceptedWorkouts,
      acceptedMetricSeries
    };
  });

  return sendJSON(res, result.duplicate ? 200 : 202, result);
}

async function handleFriendsSummary(req, res, db, tokenHashPepper) {
  const auth = await authenticateDevice(req, db, tokenHashPepper);
  if (!auth) return sendJSON(res, 401, { error: "missing_bearer_token" });

  const result = await db.withTransaction(async (tx) => {
    if (typeof tx.friendsSummary === "function") {
      return tx.friendsSummary(auth.cloudDeviceId);
    }
    return { friends: [] };
  });

  return sendJSON(res, 200, result);
}

async function handleAuthSignup(req, res, db, tokenHashPepper) {
  let input;
  try {
    input = normalizeAuthSignup(await readJSON(req));
  } catch (error) {
    return sendJSON(res, 400, { error: "invalid_auth_request", detail: error.message });
  }

  const deviceAuth = await authenticateDevice(req, db, tokenHashPepper);
  const password = makePasswordHash(input.password);
  const rawSessionToken = makeSessionToken();
  const sessionTokenHash = hashDeviceToken(rawSessionToken, tokenHashPepper);
  const result = await db.withTransaction(async (tx) => tx.signupUser({
    ...input,
    passwordHash: password.hash,
    passwordSalt: password.salt,
    sessionTokenHash,
    cloudDeviceId: deviceAuth?.cloudDeviceId ?? null
  }));
  return sendJSON(res, 201, { ...result, sessionToken: rawSessionToken });
}

async function handleAuthLogin(req, res, db, tokenHashPepper) {
  let input;
  try {
    input = normalizeAuthLogin(await readJSON(req));
  } catch (error) {
    return sendJSON(res, 400, { error: "invalid_auth_request", detail: error.message });
  }

  const deviceAuth = await authenticateDevice(req, db, tokenHashPepper);
  const rawSessionToken = makeSessionToken();
  const sessionTokenHash = hashDeviceToken(rawSessionToken, tokenHashPepper);
  const result = await db.withTransaction(async (tx) => {
    const user = await tx.findUserForLogin(input.username);
    if (!user || !verifyPassword(input.password, user.passwordSalt, user.passwordHash)) {
      throwCoded("invalid_credentials");
    }
    return tx.createAuthSession(user.id, sessionTokenHash, deviceAuth?.cloudDeviceId ?? null);
  });
  return sendJSON(res, 200, { ...result, sessionToken: rawSessionToken });
}

async function handleAuthLogout(req, res, db, tokenHashPepper) {
  const token = parseBearerToken(req.headers.authorization);
  if (!token) return sendJSON(res, 200, { loggedOut: true });
  const sessionTokenHash = hashDeviceToken(token, tokenHashPepper);
  await db.withTransaction(async (tx) => {
    if (typeof tx.deleteAuthSession === "function") {
      await tx.deleteAuthSession(sessionTokenHash);
    }
  });
  return sendJSON(res, 200, { loggedOut: true });
}

async function handleUserBootstrap(req, res, db, tokenHashPepper) {
  const auth = await authenticateActor(req, db, tokenHashPepper);
  if (!auth) return sendJSON(res, 401, { error: "missing_bearer_token" });

  let profile;
  try {
    profile = normalizeUserProfile(await readJSON(req));
  } catch (error) {
    return sendJSON(res, 400, { error: "invalid_user_profile", detail: error.message });
  }

  const result = await db.withTransaction(async (tx) => tx.bootstrapUser(auth.cloudDeviceId, profile));
  return sendJSON(res, 200, result);
}

async function handleUserMe(req, res, db, tokenHashPepper) {
  const auth = await authenticateActor(req, db, tokenHashPepper);
  if (!auth) return sendJSON(res, 401, { error: "missing_bearer_token" });
  const result = await db.withTransaction(async (tx) => tx.getUserMe(auth.cloudDeviceId));
  return sendJSON(res, 200, result);
}

async function handleUserPatch(req, res, db, tokenHashPepper) {
  const auth = await authenticateActor(req, db, tokenHashPepper);
  if (!auth) return sendJSON(res, 401, { error: "missing_bearer_token" });

  let profile;
  try {
    profile = normalizeUserProfile(await readJSON(req));
  } catch (error) {
    return sendJSON(res, 400, { error: "invalid_user_profile", detail: error.message });
  }

  const result = await db.withTransaction(async (tx) => tx.updateUserProfile(auth.cloudDeviceId, profile));
  return sendJSON(res, 200, result);
}

async function handlePrivacyPatch(req, res, db, tokenHashPepper) {
  const auth = await authenticateActor(req, db, tokenHashPepper);
  if (!auth) return sendJSON(res, 401, { error: "missing_bearer_token" });

  let privacy;
  try {
    privacy = normalizePrivacyPatch(await readJSON(req));
  } catch (error) {
    return sendJSON(res, 400, { error: "invalid_privacy", detail: error.message });
  }

  const result = await db.withTransaction(async (tx) => tx.updateUserPrivacy(auth.cloudDeviceId, privacy));
  return sendJSON(res, 200, result);
}

async function handleFriendRequest(req, res, db, tokenHashPepper) {
  const auth = await authenticateActor(req, db, tokenHashPepper);
  if (!auth) return sendJSON(res, 401, { error: "missing_bearer_token" });

  let target;
  try {
    target = normalizeFriendTarget(await readJSON(req));
  } catch (error) {
    return sendJSON(res, 400, { error: "invalid_friend_request", detail: error.message });
  }

  const result = await db.withTransaction(async (tx) => {
    const user = await requireUser(tx, auth.cloudDeviceId);
    return tx.createFriendRequest(user.id, target);
  });
  return sendJSON(res, result.created ? 201 : 200, result);
}

async function handleFriendshipAction(req, res, db, tokenHashPepper, methodName) {
  const auth = await authenticateActor(req, db, tokenHashPepper);
  if (!auth) return sendJSON(res, 401, { error: "missing_bearer_token" });

  let body;
  try {
    body = await readJSON(req);
  } catch (error) {
    return sendJSON(res, 400, { error: "invalid_friendship_action", detail: error.message });
  }

  const result = await db.withTransaction(async (tx) => {
    const user = await requireUser(tx, auth.cloudDeviceId);
    return tx[methodName](user.id, body);
  });
  return sendJSON(res, 200, result);
}

async function handleFriendsList(req, res, db, tokenHashPepper) {
  const auth = await authenticateActor(req, db, tokenHashPepper);
  if (!auth) return sendJSON(res, 401, { error: "missing_bearer_token" });
  const result = await db.withTransaction(async (tx) => {
    const user = await requireUser(tx, auth.cloudDeviceId);
    return tx.listFriends(user.id);
  });
  return sendJSON(res, 200, result);
}

async function handleFriendRequests(req, res, db, tokenHashPepper) {
  const auth = await authenticateActor(req, db, tokenHashPepper);
  if (!auth) return sendJSON(res, 401, { error: "missing_bearer_token" });
  const result = await db.withTransaction(async (tx) => {
    const user = await requireUser(tx, auth.cloudDeviceId);
    return tx.listFriendRequests(user.id);
  });
  return sendJSON(res, 200, result);
}

async function handleFriendsFeed(req, res, db, tokenHashPepper) {
  const auth = await authenticateActor(req, db, tokenHashPepper);
  if (!auth) return sendJSON(res, 401, { error: "missing_bearer_token" });
  const result = await db.withTransaction(async (tx) => {
    const user = await requireUser(tx, auth.cloudDeviceId);
    return tx.friendsFeed(user.id);
  });
  return sendJSON(res, 200, result);
}

async function authenticateDevice(req, db, tokenHashPepper) {
  const token = parseBearerToken(req.headers.authorization);
  if (!token) return null;

  const deviceTokenHash = hashDeviceToken(token, tokenHashPepper);
  const cloudDeviceId = await db.withTransaction(async (tx) => tx.findOrCreateCloudDevice(deviceTokenHash));
  return { cloudDeviceId };
}

async function authenticateActor(req, db, tokenHashPepper) {
  const token = parseBearerToken(req.headers.authorization);
  if (!token) return null;

  const tokenHash = hashDeviceToken(token, tokenHashPepper);
  const session = await db.withTransaction(async (tx) => {
    if (typeof tx.findAuthSession === "function") return tx.findAuthSession(tokenHash);
    return null;
  });
  if (session?.cloudDeviceId) {
    return { cloudDeviceId: session.cloudDeviceId, cloudUserId: session.cloudUserId };
  }

  const cloudDeviceId = await db.withTransaction(async (tx) => tx.findOrCreateCloudDevice(tokenHash));
  return { cloudDeviceId };
}

async function requireUser(tx, cloudDeviceId) {
  const me = await tx.getUserMe(cloudDeviceId);
  if (!me.user) {
    const error = new Error("user is not bootstrapped");
    error.code = "user_not_bootstrapped";
    throw error;
  }
  return me.user;
}

function duplicateResult(batch) {
  return {
    duplicate: true,
    acceptedDailyMetrics: 0,
    acceptedSleepSessions: 0,
    acceptedWorkouts: 0,
    acceptedMetricSeries: 0,
    clientBatchId: batch.clientBatchId
  };
}

function validateBatch(batch) {
  if (!batch || typeof batch !== "object") throw new Error("body must be a JSON object");
  if (!batch.clientBatchId || typeof batch.clientBatchId !== "string") throw new Error("clientBatchId is required");
  if (!batch.schemaVersion || typeof batch.schemaVersion !== "string") throw new Error("schemaVersion is required");

  for (const key of ["dailyMetrics", "sleepSessions", "workouts", "metricSeries"]) {
    if (!Array.isArray(batch[key])) {
      throw new Error(`${key} must be an array`);
    }
  }

  if (batch.sourceDeviceIds !== undefined && !Array.isArray(batch.sourceDeviceIds)) {
    throw new Error("sourceDeviceIds must be an array when present");
  }
}

function normalizeUserProfile(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("body must be a JSON object");
  }

  return {
    username: optionalTrimmedString(input.username, "username", { lower: true }),
    displayName: optionalTrimmedString(input.display_name ?? input.displayName, "display_name"),
    avatarUrl: optionalTrimmedString(input.avatar_url ?? input.avatarUrl, "avatar_url")
  };
}

function normalizeAuthSignup(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("body must be a JSON object");
  }

  return {
    username: requiredUsername(input.username),
    password: requiredPassword(input.password),
    displayName: optionalTrimmedString(input.display_name ?? input.displayName, "display_name"),
    avatarUrl: optionalTrimmedString(input.avatar_url ?? input.avatarUrl, "avatar_url")
  };
}

function normalizeAuthLogin(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("body must be a JSON object");
  }

  return {
    username: requiredUsername(input.username),
    password: requiredPassword(input.password)
  };
}

function requiredUsername(value) {
  const username = optionalTrimmedString(value, "username", { lower: true, stripAt: true });
  if (!username) throw new Error("username is required");
  return username;
}

function requiredPassword(value) {
  if (typeof value !== "string" || value.length < 8) {
    throw new Error("password must be at least 8 characters");
  }
  return value;
}

function normalizePrivacyPatch(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("body must be a JSON object");
  }

  const privacy = {};
  for (const key of ["share_recovery", "share_sleep", "share_workouts", "share_daily_effort"]) {
    if (input[key] !== undefined) {
      if (typeof input[key] !== "boolean") throw new Error(`${key} must be boolean`);
      privacy[toCamelPrivacyKey(key)] = input[key];
    }
  }
  return privacy;
}

function toCamelPrivacyKey(key) {
  return {
    share_recovery: "shareRecovery",
    share_sleep: "shareSleep",
    share_workouts: "shareWorkouts",
    share_daily_effort: "shareDailyEffort"
  }[key];
}

function normalizeFriendTarget(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("body must be a JSON object");
  }

  const username = optionalTrimmedString(input.username, "username", { lower: true, stripAt: true });
  const userId = optionalTrimmedString(input.user_id ?? input.userId, "user_id");
  if (!username && !userId) {
    throw new Error("username or user_id is required");
  }
  return { username, userId };
}

function optionalTrimmedString(value, field, options = {}) {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") throw new Error(`${field} must be a string`);
  let trimmed = value.trim();
  if (options.stripAt) trimmed = trimmed.replace(/^@+/, "");
  if (!trimmed) return null;
  return options.lower ? trimmed.toLowerCase() : trimmed;
}

async function readJSON(req) {
  const body = await readBody(req);
  if (!body.trim()) return {};
  return JSON.parse(body);
}

async function readBody(req) {
  let body = "";
  let bytes = 0;

  for await (const chunk of req) {
    bytes += chunk.length;
    if (bytes > MAX_BODY_BYTES) {
      throw new Error("request body too large");
    }
    body += chunk;
  }

  return body;
}

function sendJSON(res, statusCode, body) {
  const data = JSON.stringify(body);
  res.writeHead(statusCode, {
    "content-type": "application/json",
    "content-length": Buffer.byteLength(data)
  });
  res.end(data);
}

function throwCoded(code) {
  const error = new Error(code);
  error.code = code;
  throw error;
}
