import crypto from "node:crypto";
import pg from "pg";

const UNIQUE_VIOLATION = "23505";

export function createPostgresStore(connectionString = process.env.DATABASE_URL) {
  if (!connectionString) {
    throw new Error("DATABASE_URL is required");
  }

  const pool = new pg.Pool({ connectionString });

  return {
    async close() {
      await pool.end();
    },

    async withTransaction(callback) {
      const client = await pool.connect();
      try {
        await client.query("BEGIN");
        const tx = createTransaction(client);
        const result = await callback(tx);
        await client.query("COMMIT");
        return result;
      } catch (error) {
        await client.query("ROLLBACK");
        throw error;
      } finally {
        client.release();
      }
    }
  };
}

function createTransaction(client) {
  return {
    async findOrCreateCloudDevice(deviceTokenHash) {
      const id = crypto.randomUUID();
      const result = await client.query(
        `
        INSERT INTO cloud_device (id, device_token_hash, last_seen_at)
        VALUES ($1, $2, now())
        ON CONFLICT (device_token_hash)
        DO UPDATE SET last_seen_at = now()
        RETURNING id
        `,
        [id, deviceTokenHash]
      );
      return result.rows[0].id;
    },

    async getUserMe(cloudDeviceId) {
      const result = await client.query(
        `
        SELECT
          d.id AS device_id,
          d.cloud_user_id,
          d.created_at AS device_created_at,
          d.last_seen_at,
          u.*
        FROM cloud_device d
        LEFT JOIN cloud_user u ON u.id = d.cloud_user_id
        WHERE d.id = $1
        `,
        [cloudDeviceId]
      );
      const row = result.rows[0];
      return {
        device: row ? mapDevice(row) : null,
        user: row?.id ? mapUser(row) : null
      };
    },

    async bootstrapUser(cloudDeviceId, profile) {
      const deviceResult = await client.query("SELECT id, cloud_user_id FROM cloud_device WHERE id = $1", [cloudDeviceId]);
      const device = deviceResult.rows[0];
      if (!device) throw new Error("cloud device not found");

      let userId = device.cloud_user_id;
      if (!userId) {
        userId = crypto.randomUUID();
        try {
          await client.query(
            `
            INSERT INTO cloud_user (id, username, display_name, avatar_url)
            VALUES ($1, $2, $3, $4)
            `,
            [userId, profile.username, profile.displayName, profile.avatarUrl]
          );
        } catch (error) {
          throwUsernameConflict(error);
        }
        await client.query("UPDATE cloud_device SET cloud_user_id = $1 WHERE id = $2", [userId, cloudDeviceId]);
      } else {
        await updateUserColumns(client, userId, profile);
      }

      return this.getUserMe(cloudDeviceId);
    },

    async signupUser(input) {
      const userId = crypto.randomUUID();
      try {
        await client.query(
          `
          INSERT INTO cloud_user (id, username, display_name, avatar_url, password_hash, password_salt)
          VALUES ($1, $2, $3, $4, $5, $6)
          `,
          [userId, input.username, input.displayName, input.avatarUrl, input.passwordHash, input.passwordSalt]
        );
      } catch (error) {
        throwUsernameConflict(error);
      }

      if (input.cloudDeviceId) {
        await client.query("UPDATE cloud_device SET cloud_user_id = $1 WHERE id = $2", [userId, input.cloudDeviceId]);
      }
      return this.createAuthSession(userId, input.sessionTokenHash, input.cloudDeviceId);
    },

    async findUserForLogin(username) {
      const result = await client.query(
        `
        SELECT
          id,
          username,
          display_name,
          avatar_url,
          share_recovery,
          share_sleep,
          share_workouts,
          share_daily_effort,
          created_at,
          updated_at,
          password_hash,
          password_salt
        FROM cloud_user
        WHERE username = $1
        `,
        [username]
      );
      const row = result.rows[0];
      return row ? mapLoginUser(row) : null;
    },

    async createAuthSession(userId, sessionTokenHash, cloudDeviceId = null) {
      if (cloudDeviceId) {
        await client.query("UPDATE cloud_device SET cloud_user_id = $1 WHERE id = $2", [userId, cloudDeviceId]);
      }
      const sessionResult = await client.query(
        `
        INSERT INTO cloud_auth_session (id, cloud_user_id, cloud_device_id, session_token_hash, last_seen_at)
        VALUES ($1, $2, $3, $4, now())
        RETURNING *
        `,
        [crypto.randomUUID(), userId, cloudDeviceId, sessionTokenHash]
      );
      const userResult = await client.query("SELECT * FROM cloud_user WHERE id = $1", [userId]);
      return {
        user: mapUser(userResult.rows[0]),
        device: cloudDeviceId ? (await this.getUserMe(cloudDeviceId)).device : null,
        session: mapAuthSession(sessionResult.rows[0])
      };
    },

    async findAuthSession(sessionTokenHash) {
      const result = await client.query(
        `
        UPDATE cloud_auth_session
        SET last_seen_at = now()
        WHERE session_token_hash = $1
        RETURNING cloud_user_id, cloud_device_id
        `,
        [sessionTokenHash]
      );
      const row = result.rows[0];
      if (!row) return null;
      if (!row.cloud_device_id) {
        const deviceResult = await client.query(
          "SELECT id FROM cloud_device WHERE cloud_user_id = $1 ORDER BY last_seen_at DESC NULLS LAST, created_at DESC LIMIT 1",
          [row.cloud_user_id]
        );
        row.cloud_device_id = deviceResult.rows[0]?.id ?? null;
      }
      return {
        cloudUserId: row.cloud_user_id,
        cloudDeviceId: row.cloud_device_id
      };
    },

    async deleteAuthSession(sessionTokenHash) {
      await client.query("DELETE FROM cloud_auth_session WHERE session_token_hash = $1", [sessionTokenHash]);
      return { loggedOut: true };
    },

    async updateUserProfile(cloudDeviceId, profile) {
      const me = await this.getUserMe(cloudDeviceId);
      if (!me.user) throwCoded("user_not_bootstrapped");
      await updateUserColumns(client, me.user.id, profile);
      return this.getUserMe(cloudDeviceId);
    },

    async updateUserPrivacy(cloudDeviceId, privacy) {
      const me = await this.getUserMe(cloudDeviceId);
      if (!me.user) throwCoded("user_not_bootstrapped");

      const fields = [];
      const values = [];
      for (const [column, key] of [
        ["share_recovery", "shareRecovery"],
        ["share_sleep", "shareSleep"],
        ["share_workouts", "shareWorkouts"],
        ["share_daily_effort", "shareDailyEffort"]
      ]) {
        if (privacy[key] !== undefined) {
          values.push(privacy[key]);
          fields.push(`${column} = $${values.length}`);
        }
      }
      if (fields.length) {
        values.push(me.user.id);
        await client.query(
          `UPDATE cloud_user SET ${fields.join(", ")}, updated_at = now() WHERE id = $${values.length}`,
          values
        );
      }
      return this.getUserMe(cloudDeviceId);
    },

    async createFriendRequest(requesterUserId, target) {
      const addressee = await findUser(client, target);
      if (!addressee) throwCoded("friend_not_found");
      if (addressee.id === requesterUserId) throwCoded("cannot_friend_self");

      const existing = await findFriendshipPair(client, requesterUserId, addressee.id);
      if (existing) {
        return { created: false, friendship: mapFriendship(existing) };
      }

      const result = await client.query(
        `
        INSERT INTO cloud_friendship (id, requester_user_id, addressee_user_id, status)
        VALUES ($1, $2, $3, 'pending')
        RETURNING *
        `,
        [crypto.randomUUID(), requesterUserId, addressee.id]
      );
      return { created: true, friendship: mapFriendship(result.rows[0]) };
    },

    async acceptFriendRequest(userId, body) {
      const friendshipId = requiredId(body.friendship_id ?? body.friendshipId, "friendship_id");
      const result = await client.query(
        `
        UPDATE cloud_friendship
        SET status = 'accepted', updated_at = now()
        WHERE id = $1 AND addressee_user_id = $2 AND status = 'pending'
        RETURNING *
        `,
        [friendshipId, userId]
      );
      if (!result.rows[0]) throwCoded("friendship_not_found");
      return { friendship: mapFriendship(result.rows[0]) };
    },

    async rejectFriendRequest(userId, body) {
      const friendshipId = requiredId(body.friendship_id ?? body.friendshipId, "friendship_id");
      const result = await client.query(
        `
        DELETE FROM cloud_friendship
        WHERE id = $1 AND addressee_user_id = $2 AND status = 'pending'
        RETURNING *
        `,
        [friendshipId, userId]
      );
      if (!result.rows[0]) throwCoded("friendship_not_found");
      return { removed: true, friendshipId };
    },

    async removeFriendship(userId, body) {
      const friendshipId = body.friendship_id ?? body.friendshipId ?? null;
      const friendUserId = body.user_id ?? body.userId ?? null;

      let result;
      if (friendshipId) {
        result = await client.query(
          `
          DELETE FROM cloud_friendship
          WHERE id = $1
            AND (requester_user_id = $2 OR addressee_user_id = $2)
          RETURNING *
          `,
          [friendshipId, userId]
        );
      } else if (friendUserId) {
        result = await client.query(
          `
          DELETE FROM cloud_friendship
          WHERE (
              requester_user_id = $1 AND addressee_user_id = $2
            ) OR (
              requester_user_id = $2 AND addressee_user_id = $1
            )
          RETURNING *
          `,
          [userId, friendUserId]
        );
      } else {
        throw new Error("friendship_id or user_id is required");
      }

      if (!result.rows[0]) throwCoded("friendship_not_found");
      return { removed: true, friendshipId: result.rows[0].id };
    },

    async listFriends(userId) {
      const result = await client.query(
        `
        SELECT
          f.*,
          u.id AS friend_id,
          u.username AS friend_username,
          u.display_name AS friend_display_name,
          u.avatar_url AS friend_avatar_url,
          u.share_recovery AS friend_share_recovery,
          u.share_sleep AS friend_share_sleep,
          u.share_workouts AS friend_share_workouts,
          u.share_daily_effort AS friend_share_daily_effort,
          u.created_at AS friend_created_at,
          u.updated_at AS friend_updated_at
        FROM cloud_friendship f
        JOIN cloud_user u
          ON u.id = CASE
            WHEN f.requester_user_id = $1 THEN f.addressee_user_id
            ELSE f.requester_user_id
          END
        WHERE f.status = 'accepted'
          AND (f.requester_user_id = $1 OR f.addressee_user_id = $1)
        ORDER BY u.display_name NULLS LAST, u.username NULLS LAST, u.created_at
        `,
        [userId]
      );
      return {
        friends: result.rows.map((row) => ({
          friendship: mapFriendship(row),
          user: mapAliasedUser(row, "friend")
        }))
      };
    },

    async listFriendRequests(userId) {
      const result = await client.query(
        `
        SELECT
          f.*,
          requester.id AS requester_id,
          requester.username AS requester_username,
          requester.display_name AS requester_display_name,
          requester.avatar_url AS requester_avatar_url,
          requester.created_at AS requester_created_at,
          requester.updated_at AS requester_updated_at,
          addressee.id AS addressee_id,
          addressee.username AS addressee_username,
          addressee.display_name AS addressee_display_name,
          addressee.avatar_url AS addressee_avatar_url,
          addressee.created_at AS addressee_created_at,
          addressee.updated_at AS addressee_updated_at
        FROM cloud_friendship f
        JOIN cloud_user requester ON requester.id = f.requester_user_id
        JOIN cloud_user addressee ON addressee.id = f.addressee_user_id
        WHERE f.status = 'pending'
          AND (f.requester_user_id = $1 OR f.addressee_user_id = $1)
        ORDER BY f.created_at DESC
        `,
        [userId]
      );

      return {
        incoming: result.rows
          .filter((row) => row.addressee_user_id === userId)
          .map((row) => mapRequest(row, "requester")),
        outgoing: result.rows
          .filter((row) => row.requester_user_id === userId)
          .map((row) => mapRequest(row, "addressee"))
      };
    },

    async friendsFeed(userId) {
      const friendsResult = await client.query(
        `
        SELECT u.*
        FROM cloud_friendship f
        JOIN cloud_user u
          ON u.id = CASE
            WHEN f.requester_user_id = $1 THEN f.addressee_user_id
            ELSE f.requester_user_id
          END
        WHERE f.status = 'accepted'
          AND (f.requester_user_id = $1 OR f.addressee_user_id = $1)
        ORDER BY u.display_name NULLS LAST, u.username NULLS LAST, u.created_at
        `,
        [userId]
      );
      const friends = friendsResult.rows.map(mapUser);
      if (!friends.length) return { friends: [] };

      const friendIds = friends.map((friend) => friend.id);
      const [daily, sleep, workouts, metricSeries] = await Promise.all([
        latestDailyForUsers(client, friendIds),
        latestSleepForUsers(client, friendIds),
        recentWorkoutsForUsers(client, friendIds),
        latestMetricSeriesForUsers(client, friendIds)
      ]);

      return {
        friends: friends.map((friend) => {
          const dailyRow = daily.get(friend.id);
          const sleepRow = sleep.get(friend.id);
          const workoutRows = workouts.get(friend.id) ?? [];
          const metricRows = metricSeries.get(friend.id) ?? [];
          return {
            user: publicUser(friend),
            latestDailyMetric: dailyRow ? filterDailyMetric(dailyRow, friend) : null,
            latestSleepSession: friend.shareSleep && sleepRow ? publicSleep(sleepRow) : null,
            recentWorkouts: friend.shareWorkouts ? workoutRows.map(publicWorkout) : [],
            metricSeries: metricRows.map((row) => publicMetricSeries(row, friend)).filter(Boolean)
          };
        })
      };
    },

    async insertSyncBatch(cloudDeviceId, batch) {
      const result = await client.query(
        `
        INSERT INTO cloud_sync_batch (
          cloud_device_id,
          client_batch_id,
          schema_version,
          app_version,
          source_device_ids
        )
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT (cloud_device_id, client_batch_id) DO NOTHING
        RETURNING client_batch_id
        `,
        [
          cloudDeviceId,
          batch.clientBatchId,
          batch.schemaVersion,
          batch.appVersion ?? null,
          batch.sourceDeviceIds ?? []
        ]
      );
      return result.rowCount === 1;
    },

    async upsertDailyMetrics(cloudDeviceId, rows) {
      for (const row of rows) {
        await client.query(
          `
          INSERT INTO cloud_daily_metric (cloud_device_id, source_device_id, day, payload)
          VALUES ($1, $2, $3, $4)
          ON CONFLICT (cloud_device_id, source_device_id, day)
          DO UPDATE SET payload = EXCLUDED.payload, updated_at = now()
          `,
          [cloudDeviceId, row.sourceDeviceId, row.day, row]
        );
      }
      return rows.length;
    },

    async upsertSleepSessions(cloudDeviceId, rows) {
      for (const row of rows) {
        await client.query(
          `
          INSERT INTO cloud_sleep_session (cloud_device_id, source_device_id, start_ts, payload)
          VALUES ($1, $2, $3, $4)
          ON CONFLICT (cloud_device_id, source_device_id, start_ts)
          DO UPDATE SET payload = EXCLUDED.payload, updated_at = now()
          `,
          [cloudDeviceId, row.sourceDeviceId, row.startTs, row]
        );
      }
      return rows.length;
    },

    async upsertWorkouts(cloudDeviceId, rows) {
      for (const row of rows) {
        await client.query(
          `
          INSERT INTO cloud_workout (cloud_device_id, source_device_id, start_ts, sport, payload)
          VALUES ($1, $2, $3, $4, $5)
          ON CONFLICT (cloud_device_id, source_device_id, start_ts, sport)
          DO UPDATE SET payload = EXCLUDED.payload, updated_at = now()
          `,
          [cloudDeviceId, row.sourceDeviceId, row.startTs, row.sport, row]
        );
      }
      return rows.length;
    },

    async upsertMetricSeries(cloudDeviceId, rows) {
      for (const row of rows) {
        await client.query(
          `
          INSERT INTO cloud_metric_series (cloud_device_id, source_device_id, day, key, value)
          VALUES ($1, $2, $3, $4, $5)
          ON CONFLICT (cloud_device_id, source_device_id, day, key)
          DO UPDATE SET value = EXCLUDED.value, updated_at = now()
          `,
          [cloudDeviceId, row.sourceDeviceId, row.day, row.key, row.value]
        );
      }
      return rows.length;
    },

    async friendsSummary(cloudDeviceId) {
      const result = await client.query(
        `
        WITH latest_daily AS (
          SELECT DISTINCT ON (source_device_id)
            source_device_id,
            day,
            payload
          FROM cloud_daily_metric
          WHERE cloud_device_id = $1
          ORDER BY source_device_id, day DESC
        ),
        latest_sleep AS (
          SELECT DISTINCT ON (source_device_id)
            source_device_id,
            start_ts,
            payload
          FROM cloud_sleep_session
          WHERE cloud_device_id = $1
          ORDER BY source_device_id, start_ts DESC
        )
        SELECT
          d.source_device_id,
          d.day::text,
          d.payload,
          s.start_ts,
          s.payload AS sleep_payload
        FROM latest_daily d
        LEFT JOIN latest_sleep s
          ON s.source_device_id = d.source_device_id
        ORDER BY d.source_device_id
        `,
        [cloudDeviceId]
      );

      return {
        friends: result.rows.map((row) => {
          const payload = row.payload ?? {};
          const sleep = row.sleep_payload ?? {};
          return {
            cloudDeviceId,
            displayName: row.source_device_id,
            day: row.day,
            recovery: payload.recovery ?? null,
            effort: payload.effort ?? null,
            totalSleepMin: payload.totalSleepMin ?? null,
            sleepDebtMin: null,
            restingHr: payload.restingHr ?? sleep.restingHr ?? null,
            avgHrv: payload.avgHrv ?? sleep.avgHrv ?? null,
            steps: payload.steps ?? null,
            latestSleepStart: sleep.startTs ?? null,
            latestSleepEnd: sleep.endTs ?? null
          };
        })
      };
    }
  };
}

async function updateUserColumns(client, userId, profile) {
  const fields = [];
  const values = [];
  for (const [column, key] of [
    ["username", "username"],
    ["display_name", "displayName"],
    ["avatar_url", "avatarUrl"]
  ]) {
    if (profile[key] !== null && profile[key] !== undefined) {
      values.push(profile[key]);
      fields.push(`${column} = $${values.length}`);
    }
  }
  if (!fields.length) return;

  values.push(userId);
  try {
    await client.query(
      `UPDATE cloud_user SET ${fields.join(", ")}, updated_at = now() WHERE id = $${values.length}`,
      values
    );
  } catch (error) {
    throwUsernameConflict(error);
  }
}

async function findUser(client, target) {
  if (target.userId) {
    try {
      const result = await client.query("SELECT * FROM cloud_user WHERE id = $1", [target.userId]);
      return result.rows[0] ?? null;
    } catch (error) {
      if (error.code === "22P02") return null;
      throw error;
    }
  }
  const result = await client.query("SELECT * FROM cloud_user WHERE username = $1", [target.username]);
  return result.rows[0] ?? null;
}

async function findFriendshipPair(client, requesterUserId, addresseeUserId) {
  const result = await client.query(
    `
    SELECT *
    FROM cloud_friendship
    WHERE (
        requester_user_id = $1 AND addressee_user_id = $2
      ) OR (
        requester_user_id = $2 AND addressee_user_id = $1
      )
    `,
    [requesterUserId, addresseeUserId]
  );
  return result.rows[0] ?? null;
}

async function latestDailyForUsers(client, userIds) {
  const result = await client.query(
    `
    SELECT DISTINCT ON (d.cloud_user_id)
      d.cloud_user_id,
      m.day::text,
      m.payload,
      m.updated_at
    FROM cloud_daily_metric m
    JOIN cloud_device d ON d.id = m.cloud_device_id
    WHERE d.cloud_user_id = ANY($1::uuid[])
    ORDER BY d.cloud_user_id, m.day DESC, m.updated_at DESC
    `,
    [userIds]
  );
  return mapByUserId(result.rows);
}

async function latestSleepForUsers(client, userIds) {
  const result = await client.query(
    `
    SELECT DISTINCT ON (d.cloud_user_id)
      d.cloud_user_id,
      s.start_ts,
      s.payload,
      s.updated_at
    FROM cloud_sleep_session s
    JOIN cloud_device d ON d.id = s.cloud_device_id
    WHERE d.cloud_user_id = ANY($1::uuid[])
    ORDER BY d.cloud_user_id, s.start_ts DESC, s.updated_at DESC
    `,
    [userIds]
  );
  return mapByUserId(result.rows);
}

async function recentWorkoutsForUsers(client, userIds) {
  const result = await client.query(
    `
    SELECT *
    FROM (
      SELECT
        d.cloud_user_id,
        w.start_ts,
        w.sport,
        w.payload,
        w.updated_at,
        row_number() OVER (
          PARTITION BY d.cloud_user_id
          ORDER BY w.start_ts DESC, w.updated_at DESC
        ) AS rn
      FROM cloud_workout w
      JOIN cloud_device d ON d.id = w.cloud_device_id
      WHERE d.cloud_user_id = ANY($1::uuid[])
    ) ranked
    WHERE rn <= 5
    ORDER BY cloud_user_id, start_ts DESC
    `,
    [userIds]
  );
  return groupByUserId(result.rows);
}

async function latestMetricSeriesForUsers(client, userIds) {
  const result = await client.query(
    `
    SELECT *
    FROM (
      SELECT
        d.cloud_user_id,
        m.day::text,
        m.key,
        m.value,
        m.updated_at,
        row_number() OVER (
          PARTITION BY d.cloud_user_id, m.key
          ORDER BY m.day DESC, m.updated_at DESC
        ) AS rn
      FROM cloud_metric_series m
      JOIN cloud_device d ON d.id = m.cloud_device_id
      WHERE d.cloud_user_id = ANY($1::uuid[])
    ) ranked
    WHERE rn = 1
    ORDER BY cloud_user_id, key
    `,
    [userIds]
  );
  return groupByUserId(result.rows);
}

function mapByUserId(rows) {
  return new Map(rows.map((row) => [row.cloud_user_id, row]));
}

function groupByUserId(rows) {
  const grouped = new Map();
  for (const row of rows) {
    const group = grouped.get(row.cloud_user_id) ?? [];
    group.push(row);
    grouped.set(row.cloud_user_id, group);
  }
  return grouped;
}

function filterDailyMetric(row, user) {
  const payload = row.payload ?? {};
  return {
    day: row.day,
    recovery: user.shareRecovery ? payload.recovery ?? null : null,
    effort: user.shareDailyEffort ? payload.effort ?? payload.strain ?? null : null,
    totalSleepMin: user.shareSleep ? payload.totalSleepMin ?? null : null,
    restingHr: payload.restingHr ?? null,
    avgHrv: payload.avgHrv ?? null,
    steps: payload.steps ?? null
  };
}

function publicSleep(row) {
  const payload = row.payload ?? {};
  return {
    startTs: payload.startTs ?? row.start_ts ?? null,
    endTs: payload.endTs ?? null,
    totalSleepMin: payload.totalSleepMin ?? null,
    efficiency: payload.efficiency ?? null
  };
}

function publicWorkout(row) {
  const payload = row.payload ?? {};
  return {
    startTs: payload.startTs ?? row.start_ts ?? null,
    endTs: payload.endTs ?? null,
    sport: payload.sport ?? row.sport ?? null,
    effort: payload.effort ?? payload.strain ?? null,
    calories: payload.calories ?? null
  };
}

function publicMetricSeries(row, user) {
  if (!user.shareSleep && row.key.startsWith("sleep_")) return null;
  if (!user.shareDailyEffort && (row.key.includes("strain") || row.key.includes("effort"))) return null;
  if (!user.shareRecovery && row.key.includes("recovery")) return null;
  return {
    day: row.day,
    key: row.key,
    value: row.value
  };
}

function publicUser(user) {
  return {
    id: user.id,
    username: user.username,
    displayName: user.displayName,
    avatarUrl: user.avatarUrl
  };
}

function mapDevice(row) {
  return {
    id: row.device_id,
    cloudUserId: row.cloud_user_id,
    createdAt: row.device_created_at,
    lastSeenAt: row.last_seen_at
  };
}

function mapUser(row) {
  return {
    id: row.id,
    username: row.username,
    displayName: row.display_name,
    avatarUrl: row.avatar_url,
    shareRecovery: row.share_recovery,
    shareSleep: row.share_sleep,
    shareWorkouts: row.share_workouts,
    shareDailyEffort: row.share_daily_effort,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function mapLoginUser(row) {
  return {
    ...mapUser(row),
    passwordHash: row.password_hash,
    passwordSalt: row.password_salt
  };
}

function mapAuthSession(row) {
  return {
    id: row.id,
    cloudUserId: row.cloud_user_id,
    cloudDeviceId: row.cloud_device_id,
    createdAt: row.created_at,
    lastSeenAt: row.last_seen_at
  };
}

function mapAliasedUser(row, prefix) {
  return {
    id: row[`${prefix}_id`],
    username: row[`${prefix}_username`],
    displayName: row[`${prefix}_display_name`],
    avatarUrl: row[`${prefix}_avatar_url`],
    shareRecovery: row[`${prefix}_share_recovery`],
    shareSleep: row[`${prefix}_share_sleep`],
    shareWorkouts: row[`${prefix}_share_workouts`],
    shareDailyEffort: row[`${prefix}_share_daily_effort`],
    createdAt: row[`${prefix}_created_at`],
    updatedAt: row[`${prefix}_updated_at`]
  };
}

function mapFriendship(row) {
  return {
    id: row.id,
    requesterUserId: row.requester_user_id,
    addresseeUserId: row.addressee_user_id,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function mapRequest(row, prefix) {
  return {
    friendship: mapFriendship(row),
    user: {
      id: row[`${prefix}_id`],
      username: row[`${prefix}_username`],
      displayName: row[`${prefix}_display_name`],
      avatarUrl: row[`${prefix}_avatar_url`],
      createdAt: row[`${prefix}_created_at`],
      updatedAt: row[`${prefix}_updated_at`]
    }
  };
}

function requiredId(value, field) {
  if (!value || typeof value !== "string") throw new Error(`${field} is required`);
  return value;
}

function throwUsernameConflict(error) {
  if (error.code === UNIQUE_VIOLATION) throwCoded("username_conflict");
  throw error;
}

function throwCoded(code) {
  const error = new Error(code);
  error.code = code;
  throw error;
}
