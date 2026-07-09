import assert from "node:assert/strict";
import { Readable } from "node:stream";
import test from "node:test";
import { createApp } from "../src/app.js";
import { hashDeviceToken, parseBearerToken, verifyPassword } from "../src/token.js";

test("parseBearerToken accepts bearer auth only", () => {
  assert.equal(parseBearerToken("Bearer abc"), "abc");
  assert.equal(parseBearerToken("bearer abc"), "abc");
  assert.equal(parseBearerToken("Basic abc"), null);
  assert.equal(parseBearerToken(undefined), null);
});

test("hashDeviceToken hashes server side with pepper", () => {
  const hash = hashDeviceToken("secret-token", "pepper");
  assert.equal(hash.length, 64);
  assert.notEqual(hash, "secret-token");
  assert.equal(hash, hashDeviceToken("secret-token", "pepper"));
});

test("POST /v1/sync/batch authenticates and stores batch idempotently", async () => {
  const db = new MemoryStore();
  const app = createApp({ db, tokenHashPepper: "test-pepper" });
  const batch = {
    clientBatchId: "batch-1",
    schemaVersion: "noop-cloud-sync-v1",
    appVersion: "test",
    sourceDeviceIds: ["my-whoop", "my-whoop-noop"],
    dailyMetrics: [
      { sourceDeviceId: "my-whoop", day: "2026-07-05", effort: 53.94 },
      { sourceDeviceId: "my-whoop-noop", day: "2026-07-05", effort: 12.3 }
    ],
    sleepSessions: [{ sourceDeviceId: "my-whoop", startTs: 1, endTs: 2 }],
    workouts: [{ sourceDeviceId: "my-whoop", startTs: 3, endTs: 4, sport: "run" }],
    metricSeries: [{ sourceDeviceId: "my-whoop-noop", day: "2026-07-05", key: "vitality", value: 71 }]
  };

  const first = await invokeJSON(app, "POST", "/v1/sync/batch", batch, "device-token");
  assert.equal(first.statusCode, 202);
  assert.equal(first.body.duplicate, false);
  assert.equal(first.body.acceptedDailyMetrics, 2);
  assert.equal(first.body.acceptedSleepSessions, 1);
  assert.equal(first.body.acceptedWorkouts, 1);
  assert.equal(first.body.acceptedMetricSeries, 1);

  const second = await invokeJSON(app, "POST", "/v1/sync/batch", batch, "device-token");
  assert.equal(second.statusCode, 200);
  assert.equal(second.body.duplicate, true);
  assert.equal(second.body.acceptedDailyMetrics, 0);

  assert.equal(db.devices.size, 1);
  assert.equal(db.dailyMetrics.size, 2);
  assert.equal(db.sleepSessions.size, 1);
  assert.equal(db.workouts.size, 1);
  assert.equal(db.metricSeries.size, 1);
});

test("POST /v1/sync/batch rejects missing bearer token", async () => {
  const db = new MemoryStore();
  const app = createApp({ db });

  const response = await invoke(app, {
    method: "POST",
    url: "/v1/sync/batch",
    body: JSON.stringify({ clientBatchId: "batch-1", schemaVersion: "x", dailyMetrics: [], sleepSessions: [], workouts: [], metricSeries: [] }),
    headers: { "content-type": "application/json" }
  });

  assert.equal(response.statusCode, 401);
  assert.equal(response.body.error, "missing_bearer_token");
});

test("GET /v1/friends/summary returns synced self cards", async () => {
  const db = new MemoryStore();
  const app = createApp({ db, tokenHashPepper: "test-pepper" });

  await invokeJSON(app, "POST", "/v1/sync/batch", {
    clientBatchId: "batch-1",
    schemaVersion: "noop-cloud-sync-v1",
    sourceDeviceIds: ["my-whoop"],
    dailyMetrics: [{ sourceDeviceId: "my-whoop", day: "2026-07-05", recovery: 80, effort: 42, totalSleepMin: 420, restingHr: 52, avgHrv: 88, steps: 9000 }],
    sleepSessions: [{ sourceDeviceId: "my-whoop", startTs: 11, endTs: 22 }],
    workouts: [],
    metricSeries: []
  }, "device-token");

  const response = await invoke(app, {
    method: "GET",
    url: "/v1/friends/summary",
    headers: { "authorization": "Bearer device-token" }
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.body.friends.length, 1);
  assert.equal(response.body.friends[0].displayName, "my-whoop");
  assert.equal(response.body.friends[0].recovery, 80);
  assert.equal(response.body.friends[0].latestSleepStart, 11);
});

test("user bootstrap creates and binds a cloud user to the device", async () => {
  const db = new MemoryStore();
  const app = createApp({ db });

  const bootstrap = await invokeJSON(app, "POST", "/v1/user/bootstrap", {
    username: "Ada",
    display_name: "Ada Lovelace",
    avatar_url: "https://example.test/ada.png"
  }, "ada-device");

  assert.equal(bootstrap.statusCode, 200);
  assert.equal(bootstrap.body.user.username, "ada");
  assert.equal(bootstrap.body.user.displayName, "Ada Lovelace");
  assert.equal(bootstrap.body.device.cloudUserId, bootstrap.body.user.id);

  const me = await invoke(app, {
    method: "GET",
    url: "/v1/user/me",
    headers: { authorization: "Bearer ada-device" }
  });
  assert.equal(me.statusCode, 200);
  assert.equal(me.body.user.id, bootstrap.body.user.id);
});

test("duplicate username returns conflict", async () => {
  const db = new MemoryStore();
  const app = createApp({ db });

  assert.equal((await invokeJSON(app, "POST", "/v1/user/bootstrap", { username: "ada" }, "device-a")).statusCode, 200);
  const duplicate = await invokeJSON(app, "POST", "/v1/user/bootstrap", { username: "ada" }, "device-b");

  assert.equal(duplicate.statusCode, 409);
  assert.equal(duplicate.body.error, "username_conflict");
});

test("auth signup, login, session restore, and logout work without username conflict on login", async () => {
  const db = new MemoryStore();
  const app = createApp({ db });

  const signup = await invokeJSON(app, "POST", "/v1/auth/signup", {
    username: " @Ada ",
    display_name: "Ada Lovelace",
    password: "correct horse battery"
  }, "ada-device");
  assert.equal(signup.statusCode, 201);
  assert.equal(signup.body.user.username, "ada");
  assert.ok(signup.body.sessionToken);
  assert.equal(signup.body.device.cloudUserId, signup.body.user.id);

  const duplicateSignup = await invokeJSON(app, "POST", "/v1/auth/signup", {
    username: "ada",
    password: "another password"
  }, "other-device");
  assert.equal(duplicateSignup.statusCode, 409);

  const login = await invokeJSON(app, "POST", "/v1/auth/login", {
    username: "ada",
    password: "correct horse battery"
  }, "ada-device");
  assert.equal(login.statusCode, 200);
  assert.equal(login.body.user.id, signup.body.user.id);
  assert.ok(login.body.sessionToken);

  const me = await invoke(app, {
    method: "GET",
    url: "/v1/user/me",
    headers: { authorization: `Bearer ${login.body.sessionToken}` }
  });
  assert.equal(me.statusCode, 200);
  assert.equal(me.body.user.username, "ada");

  const bad = await invokeJSON(app, "POST", "/v1/auth/login", {
    username: "ada",
    password: "wrong password"
  }, "ada-device");
  assert.equal(bad.statusCode, 401);
  assert.equal(bad.body.error, "invalid_credentials");

  const logout = await invoke(app, {
    method: "POST",
    url: "/v1/auth/logout",
    headers: { authorization: `Bearer ${login.body.sessionToken}` }
  });
  assert.equal(logout.statusCode, 200);

  const afterLogout = await invoke(app, {
    method: "GET",
    url: "/v1/user/me",
    headers: { authorization: `Bearer ${login.body.sessionToken}` }
  });
  assert.equal(afterLogout.statusCode, 200);
  assert.equal(afterLogout.body.user, null);
});

test("friend request, accept, list, reject, and remove work", async () => {
  const db = new MemoryStore();
  const app = createApp({ db });

  const alice = (await invokeJSON(app, "POST", "/v1/user/bootstrap", { username: "alice" }, "alice-device")).body.user;
  const bob = (await invokeJSON(app, "POST", "/v1/user/bootstrap", { username: "bob" }, "bob-device")).body.user;
  await invokeJSON(app, "POST", "/v1/user/bootstrap", { username: "cora" }, "cora-device");

  const requested = await invokeJSON(app, "POST", "/v1/friends/request", { username: "bob" }, "alice-device");
  assert.equal(requested.statusCode, 201);
  assert.equal(requested.body.friendship.status, "pending");

  const bobRequests = await invoke(app, {
    method: "GET",
    url: "/v1/friends/requests",
    headers: { authorization: "Bearer bob-device" }
  });
  assert.equal(bobRequests.body.incoming.length, 1);
  assert.equal(bobRequests.body.incoming[0].user.username, "alice");

  const accepted = await invokeJSON(app, "POST", "/v1/friends/accept", {
    friendship_id: requested.body.friendship.id
  }, "bob-device");
  assert.equal(accepted.statusCode, 200);
  assert.equal(accepted.body.friendship.status, "accepted");

  const aliceFriends = await invoke(app, {
    method: "GET",
    url: "/v1/friends",
    headers: { authorization: "Bearer alice-device" }
  });
  assert.equal(aliceFriends.body.friends.length, 1);
  assert.equal(aliceFriends.body.friends[0].user.id, bob.id);

  const removed = await invokeJSON(app, "POST", "/v1/friends/remove", { user_id: bob.id }, "alice-device");
  assert.equal(removed.statusCode, 200);
  assert.equal(removed.body.removed, true);

  const rejectedRequest = await invokeJSON(app, "POST", "/v1/friends/request", { username: "cora" }, "alice-device");
  const rejected = await invokeJSON(app, "POST", "/v1/friends/reject", {
    friendship_id: rejectedRequest.body.friendship.id
  }, "cora-device");
  assert.equal(rejected.statusCode, 200);
  assert.equal(rejected.body.removed, true);
});

test("friends feed uses snapshot tables and respects privacy", async () => {
  const db = new MemoryStore();
  const app = createApp({ db });

  await invokeJSON(app, "POST", "/v1/user/bootstrap", { username: "alice", display_name: "Alice" }, "alice-device");
  await invokeJSON(app, "POST", "/v1/user/bootstrap", { username: "bob", display_name: "Bob" }, "bob-device");
  const friendship = await invokeJSON(app, "POST", "/v1/friends/request", { username: "bob" }, "alice-device");
  await invokeJSON(app, "POST", "/v1/friends/accept", { friendship_id: friendship.body.friendship.id }, "bob-device");

  await invokeJSON(app, "POST", "/v1/sync/batch", {
    clientBatchId: "bob-batch-1",
    schemaVersion: "noop-cloud-sync-v1",
    sourceDeviceIds: ["my-whoop", "my-whoop-noop"],
    dailyMetrics: [{ sourceDeviceId: "my-whoop", day: "2026-07-05", recovery: 91, effort: 44, totalSleepMin: 420, restingHr: 50, avgHrv: 100, steps: 12000 }],
    sleepSessions: [{ sourceDeviceId: "my-whoop", startTs: 100, endTs: 200, totalSleepMin: 420 }],
    workouts: [{ sourceDeviceId: "my-whoop", startTs: 300, endTs: 400, sport: "run", effort: 20 }],
    metricSeries: [
      { sourceDeviceId: "my-whoop", day: "2026-07-05", key: "sleep_debt_min", value: 30 },
      { sourceDeviceId: "my-whoop-noop", day: "2026-07-05", key: "vitality", value: 75 }
    ]
  }, "bob-device");

  let feed = await invoke(app, {
    method: "GET",
    url: "/v1/friends/feed",
    headers: { authorization: "Bearer alice-device" }
  });
  assert.equal(feed.statusCode, 200);
  assert.equal(feed.body.friends.length, 1);
  assert.equal(feed.body.friends[0].latestDailyMetric.recovery, 91);
  assert.equal(feed.body.friends[0].latestDailyMetric.effort, 44);
  assert.equal(feed.body.friends[0].latestSleepSession.startTs, 100);
  assert.equal(feed.body.friends[0].recentWorkouts.length, 1);

  await invokeJSON(app, "PATCH", "/v1/user/privacy", {
    share_recovery: false,
    share_sleep: false,
    share_workouts: false,
    share_daily_effort: false
  }, "bob-device");

  feed = await invoke(app, {
    method: "GET",
    url: "/v1/friends/feed",
    headers: { authorization: "Bearer alice-device" }
  });
  const bobFeed = feed.body.friends[0];
  assert.equal(bobFeed.latestDailyMetric.recovery, null);
  assert.equal(bobFeed.latestDailyMetric.effort, null);
  assert.equal(bobFeed.latestDailyMetric.totalSleepMin, null);
  assert.equal(bobFeed.latestDailyMetric.steps, 12000);
  assert.equal(bobFeed.latestSleepSession, null);
  assert.deepEqual(bobFeed.recentWorkouts, []);
  assert.equal(bobFeed.metricSeries.some((row) => row.key === "sleep_debt_min"), false);
  assert.equal(bobFeed.metricSeries.some((row) => row.key === "vitality"), true);

  assert.equal(JSON.stringify(feed.body).includes("device_token_hash"), false);
});

function invokeJSON(app, method, url, body, token) {
  return invoke(app, {
    method,
    url,
    body: JSON.stringify(body),
    headers: {
      "authorization": `Bearer ${token}`,
      "content-type": "application/json"
    }
  });
}

async function invoke(app, options) {
  const req = Readable.from(options.body ? [options.body] : []);
  req.method = options.method;
  req.url = options.url;
  req.headers = options.headers ?? {};

  let statusCode = 200;
  let rawBody = "";
  const res = {
    writeHead(code) {
      statusCode = code;
    },
    end(data) {
      rawBody = data?.toString() ?? "";
    }
  };

  await app(req, res);
  return { statusCode, body: JSON.parse(rawBody) };
}

class MemoryStore {
  constructor() {
    this.devices = new Map();
    this.deviceIds = new Map();
    this.users = new Map();
    this.usernameIndex = new Map();
    this.sessions = new Map();
    this.friendships = new Map();
    this.batches = new Set();
    this.dailyMetrics = new Map();
    this.sleepSessions = new Map();
    this.workouts = new Map();
    this.metricSeries = new Map();
    this.nextId = 1;
  }

  async withTransaction(callback) {
    return callback(this);
  }

  async findOrCreateCloudDevice(deviceTokenHash) {
    if (!this.devices.has(deviceTokenHash)) {
      const device = {
        id: `cloud-device-${this.nextId++}`,
        cloudUserId: null,
        createdAt: new Date().toISOString(),
        lastSeenAt: new Date().toISOString()
      };
      this.devices.set(deviceTokenHash, device);
      this.deviceIds.set(device.id, device);
    }
    const device = this.devices.get(deviceTokenHash);
    device.lastSeenAt = new Date().toISOString();
    return device.id;
  }

  async getUserMe(cloudDeviceId) {
    const device = this.deviceIds.get(cloudDeviceId);
    const user = device?.cloudUserId ? this.users.get(device.cloudUserId) : null;
    return {
      device: device ? { ...device } : null,
      user: user ? sanitizeUser(user) : null
    };
  }

  async bootstrapUser(cloudDeviceId, profile) {
    const device = this.deviceIds.get(cloudDeviceId);
    if (!device.cloudUserId) {
      const user = this.createUser(profile);
      device.cloudUserId = user.id;
    } else {
      this.updateUser(device.cloudUserId, profile);
    }
    return this.getUserMe(cloudDeviceId);
  }

  async signupUser(input) {
    const user = this.createUser({
      username: input.username,
      displayName: input.displayName,
      avatarUrl: input.avatarUrl,
      passwordHash: input.passwordHash,
      passwordSalt: input.passwordSalt
    });
    if (input.cloudDeviceId) {
      const device = this.deviceIds.get(input.cloudDeviceId);
      if (device) device.cloudUserId = user.id;
    }
    return this.createAuthSession(user.id, input.sessionTokenHash, input.cloudDeviceId);
  }

  async findUserForLogin(username) {
    const id = this.usernameIndex.get(username);
    const user = id ? this.users.get(id) : null;
    return user ? { ...user } : null;
  }

  async createAuthSession(userId, sessionTokenHash, cloudDeviceId = null) {
    if (cloudDeviceId) {
      const device = this.deviceIds.get(cloudDeviceId);
      if (device) device.cloudUserId = userId;
    }
    const session = {
      id: `session-${this.nextId++}`,
      cloudUserId: userId,
      cloudDeviceId,
      createdAt: new Date().toISOString(),
      lastSeenAt: new Date().toISOString()
    };
    this.sessions.set(sessionTokenHash, session);
    const user = this.users.get(userId);
    return {
      user: sanitizeUser(user),
      device: cloudDeviceId ? (await this.getUserMe(cloudDeviceId)).device : null,
      session: { ...session }
    };
  }

  async findAuthSession(sessionTokenHash) {
    const session = this.sessions.get(sessionTokenHash);
    if (!session) return null;
    session.lastSeenAt = new Date().toISOString();
    return { ...session };
  }

  async deleteAuthSession(sessionTokenHash) {
    this.sessions.delete(sessionTokenHash);
    return { loggedOut: true };
  }

  async updateUserProfile(cloudDeviceId, profile) {
    const me = await this.getUserMe(cloudDeviceId);
    if (!me.user) throwCoded("user_not_bootstrapped");
    this.updateUser(me.user.id, profile);
    return this.getUserMe(cloudDeviceId);
  }

  async updateUserPrivacy(cloudDeviceId, privacy) {
    const me = await this.getUserMe(cloudDeviceId);
    if (!me.user) throwCoded("user_not_bootstrapped");
    const user = this.users.get(me.user.id);
    Object.assign(user, privacy, { updatedAt: new Date().toISOString() });
    return this.getUserMe(cloudDeviceId);
  }

  async createFriendRequest(requesterUserId, target) {
    const addressee = this.findUser(target);
    if (!addressee) throwCoded("friend_not_found");
    if (requesterUserId === addressee.id) throwCoded("cannot_friend_self");

    const existing = this.findFriendshipPair(requesterUserId, addressee.id);
    if (existing) return { created: false, friendship: { ...existing } };

    const friendship = {
      id: `friendship-${this.nextId++}`,
      requesterUserId,
      addresseeUserId: addressee.id,
      status: "pending",
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    this.friendships.set(friendship.id, friendship);
    return { created: true, friendship: { ...friendship } };
  }

  async acceptFriendRequest(userId, body) {
    const friendship = this.friendships.get(body.friendship_id ?? body.friendshipId);
    if (!friendship || friendship.addresseeUserId !== userId || friendship.status !== "pending") {
      throwCoded("friendship_not_found");
    }
    friendship.status = "accepted";
    friendship.updatedAt = new Date().toISOString();
    return { friendship: { ...friendship } };
  }

  async rejectFriendRequest(userId, body) {
    const id = body.friendship_id ?? body.friendshipId;
    const friendship = this.friendships.get(id);
    if (!friendship || friendship.addresseeUserId !== userId || friendship.status !== "pending") {
      throwCoded("friendship_not_found");
    }
    this.friendships.delete(id);
    return { removed: true, friendshipId: id };
  }

  async removeFriendship(userId, body) {
    const byId = body.friendship_id ?? body.friendshipId;
    const byUser = body.user_id ?? body.userId;
    let friendship = byId ? this.friendships.get(byId) : this.findFriendshipPair(userId, byUser);
    if (!friendship || ![friendship.requesterUserId, friendship.addresseeUserId].includes(userId)) {
      throwCoded("friendship_not_found");
    }
    this.friendships.delete(friendship.id);
    return { removed: true, friendshipId: friendship.id };
  }

  async listFriends(userId) {
    return {
      friends: [...this.friendships.values()]
        .filter((friendship) => friendship.status === "accepted" && [friendship.requesterUserId, friendship.addresseeUserId].includes(userId))
        .map((friendship) => ({
          friendship: { ...friendship },
          user: sanitizeUser(this.users.get(otherUserId(friendship, userId)))
        }))
    };
  }

  async listFriendRequests(userId) {
    const pending = [...this.friendships.values()].filter((friendship) => friendship.status === "pending");
    return {
      incoming: pending
        .filter((friendship) => friendship.addresseeUserId === userId)
        .map((friendship) => ({ friendship: { ...friendship }, user: sanitizeUser(this.users.get(friendship.requesterUserId)) })),
      outgoing: pending
        .filter((friendship) => friendship.requesterUserId === userId)
        .map((friendship) => ({ friendship: { ...friendship }, user: sanitizeUser(this.users.get(friendship.addresseeUserId)) }))
    };
  }

  async friendsFeed(userId) {
    const friends = (await this.listFriends(userId)).friends.map((entry) => entry.user);
    return {
      friends: friends.map((friend) => {
        const deviceIds = [...this.deviceIds.values()].filter((device) => device.cloudUserId === friend.id).map((device) => device.id);
        const latestDaily = latest([...this.dailyMetrics.values()].filter((row) => deviceIds.includes(row.cloudDeviceId)), "day");
        const latestSleep = latest([...this.sleepSessions.values()].filter((row) => deviceIds.includes(row.cloudDeviceId)), "startTs");
        const workouts = [...this.workouts.values()].filter((row) => deviceIds.includes(row.cloudDeviceId)).sort((a, b) => b.startTs - a.startTs).slice(0, 5);
        const series = latestMetricSeries([...this.metricSeries.values()].filter((row) => deviceIds.includes(row.cloudDeviceId)));
        return {
          user: publicUser(friend),
          latestDailyMetric: latestDaily ? filterDaily(latestDaily, friend) : null,
          latestSleepSession: friend.shareSleep && latestSleep ? publicSleep(latestSleep) : null,
          recentWorkouts: friend.shareWorkouts ? workouts.map(publicWorkout) : [],
          metricSeries: series.map((row) => publicMetric(row, friend)).filter(Boolean)
        };
      })
    };
  }

  async insertSyncBatch(cloudDeviceId, batch) {
    const key = `${cloudDeviceId}:${batch.clientBatchId}`;
    if (this.batches.has(key)) return false;
    this.batches.add(key);
    return true;
  }

  async upsertDailyMetrics(cloudDeviceId, rows) {
    for (const row of rows) {
      this.dailyMetrics.set(`${cloudDeviceId}:${row.sourceDeviceId}:${row.day}`, { ...row, cloudDeviceId });
    }
    return rows.length;
  }

  async upsertSleepSessions(cloudDeviceId, rows) {
    for (const row of rows) {
      this.sleepSessions.set(`${cloudDeviceId}:${row.sourceDeviceId}:${row.startTs}`, { ...row, cloudDeviceId });
    }
    return rows.length;
  }

  async upsertWorkouts(cloudDeviceId, rows) {
    for (const row of rows) {
      this.workouts.set(`${cloudDeviceId}:${row.sourceDeviceId}:${row.startTs}:${row.sport}`, { ...row, cloudDeviceId });
    }
    return rows.length;
  }

  async upsertMetricSeries(cloudDeviceId, rows) {
    for (const row of rows) {
      this.metricSeries.set(`${cloudDeviceId}:${row.sourceDeviceId}:${row.day}:${row.key}`, { ...row, cloudDeviceId });
    }
    return rows.length;
  }

  async friendsSummary(cloudDeviceId) {
    const friends = [];
    for (const [key, daily] of this.dailyMetrics.entries()) {
      if (!key.startsWith(`${cloudDeviceId}:`)) continue;
      const sleep = this.sleepSessions.get(`${cloudDeviceId}:${daily.sourceDeviceId}:11`);
      friends.push({
        cloudDeviceId,
        displayName: daily.sourceDeviceId,
        day: daily.day,
        recovery: daily.recovery ?? null,
        effort: daily.effort ?? null,
        totalSleepMin: daily.totalSleepMin ?? null,
        sleepDebtMin: null,
        restingHr: daily.restingHr ?? null,
        avgHrv: daily.avgHrv ?? null,
        steps: daily.steps ?? null,
        latestSleepStart: sleep?.startTs ?? null,
        latestSleepEnd: sleep?.endTs ?? null
      });
    }
    return { friends };
  }

  createUser(profile) {
    if (profile.username && this.usernameIndex.has(profile.username)) throwCoded("username_conflict");
    const user = {
      id: `user-${this.nextId++}`,
      username: profile.username,
      displayName: profile.displayName,
      avatarUrl: profile.avatarUrl,
      passwordHash: profile.passwordHash,
      passwordSalt: profile.passwordSalt,
      shareRecovery: true,
      shareSleep: true,
      shareWorkouts: true,
      shareDailyEffort: true,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    this.users.set(user.id, user);
    if (user.username) this.usernameIndex.set(user.username, user.id);
    return user;
  }

  updateUser(userId, profile) {
    const user = this.users.get(userId);
    if (profile.username && this.usernameIndex.get(profile.username) && this.usernameIndex.get(profile.username) !== userId) {
      throwCoded("username_conflict");
    }
    if (profile.username) {
      if (user.username) this.usernameIndex.delete(user.username);
      user.username = profile.username;
      this.usernameIndex.set(user.username, user.id);
    }
    if (profile.displayName) user.displayName = profile.displayName;
    if (profile.avatarUrl) user.avatarUrl = profile.avatarUrl;
    user.updatedAt = new Date().toISOString();
  }

  findUser(target) {
    if (target.userId) return this.users.get(target.userId) ?? null;
    const id = this.usernameIndex.get(target.username);
    return id ? this.users.get(id) : null;
  }

  findFriendshipPair(a, b) {
    return [...this.friendships.values()].find((friendship) =>
      (friendship.requesterUserId === a && friendship.addresseeUserId === b) ||
      (friendship.requesterUserId === b && friendship.addresseeUserId === a)
    ) ?? null;
  }
}

function latest(rows, key) {
  return rows.sort((a, b) => String(b[key]).localeCompare(String(a[key])))[0] ?? null;
}

function latestMetricSeries(rows) {
  const byKey = new Map();
  for (const row of rows.sort((a, b) => String(b.day).localeCompare(String(a.day)))) {
    if (!byKey.has(row.key)) byKey.set(row.key, row);
  }
  return [...byKey.values()];
}

function filterDaily(row, user) {
  return {
    day: row.day,
    recovery: user.shareRecovery ? row.recovery ?? null : null,
    effort: user.shareDailyEffort ? row.effort ?? row.strain ?? null : null,
    totalSleepMin: user.shareSleep ? row.totalSleepMin ?? null : null,
    restingHr: row.restingHr ?? null,
    avgHrv: row.avgHrv ?? null,
    steps: row.steps ?? null
  };
}

function publicSleep(row) {
  return {
    startTs: row.startTs ?? null,
    endTs: row.endTs ?? null,
    totalSleepMin: row.totalSleepMin ?? null,
    efficiency: row.efficiency ?? null
  };
}

function publicWorkout(row) {
  return {
    startTs: row.startTs ?? null,
    endTs: row.endTs ?? null,
    sport: row.sport ?? null,
    effort: row.effort ?? row.strain ?? null,
    calories: row.calories ?? null
  };
}

function publicMetric(row, user) {
  if (!user.shareSleep && row.key.startsWith("sleep_")) return null;
  if (!user.shareDailyEffort && (row.key.includes("strain") || row.key.includes("effort"))) return null;
  if (!user.shareRecovery && row.key.includes("recovery")) return null;
  return { day: row.day, key: row.key, value: row.value };
}

function publicUser(user) {
  return {
    id: user.id,
    username: user.username,
    displayName: user.displayName,
    avatarUrl: user.avatarUrl
  };
}

function sanitizeUser(user) {
  if (!user) return null;
  const { passwordHash, passwordSalt, ...safe } = user;
  return safe;
}

function otherUserId(friendship, userId) {
  return friendship.requesterUserId === userId ? friendship.addresseeUserId : friendship.requesterUserId;
}

function throwCoded(code) {
  const error = new Error(code);
  error.code = code;
  throw error;
}
