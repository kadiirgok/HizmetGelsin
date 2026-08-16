START TRANSACTION;

ALTER TABLE "Users" ADD "FirebaseUid" character varying(128);

CREATE UNIQUE INDEX "IX_Users_FirebaseUid" ON "Users" ("FirebaseUid");

INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion")
VALUES ('20260722110539_AddFirebaseUidToUser', '8.0.11');

COMMIT;

START TRANSACTION;

DROP INDEX "IX_OtpCodes_PhoneNumber";

ALTER TABLE "OtpCodes" ADD "Purpose" integer NOT NULL DEFAULT 0;

ALTER TABLE "OtpCodes" ADD "Subject" character varying(128);

CREATE INDEX "IX_OtpCodes_PhoneNumber_Purpose" ON "OtpCodes" ("PhoneNumber", "Purpose");

INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion")
VALUES ('20260722113053_AddOtpPurposeAndSubject', '8.0.11');

COMMIT;

START TRANSACTION;

DROP INDEX "IX_Users_FirebaseUid";

DROP INDEX "IX_Users_PhoneNumber";

CREATE UNIQUE INDEX "IX_Users_Email_Role" ON "Users" ("Email", "Role");

CREATE UNIQUE INDEX "IX_Users_FirebaseUid_Role" ON "Users" ("FirebaseUid", "Role");

CREATE UNIQUE INDEX "IX_Users_PhoneNumber_Role" ON "Users" ("PhoneNumber", "Role");

INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion")
VALUES ('20260724173642_AllowMultipleRolesPerEmailPhone', '8.0.11');

COMMIT;

START TRANSACTION;

DROP INDEX "IX_OtpCodes_PhoneNumber_Purpose";

ALTER TABLE "OtpCodes" ALTER COLUMN "PhoneNumber" DROP NOT NULL;

ALTER TABLE "OtpCodes" ADD "Email" character varying(200);

CREATE INDEX "IX_OtpCodes_PhoneNumber_Email_Purpose" ON "OtpCodes" ("PhoneNumber", "Email", "Purpose");

INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion")
VALUES ('20260724173801_AddEmailToOtpCode', '8.0.11');

COMMIT;

START TRANSACTION;

CREATE TABLE IF NOT EXISTS "UserNotificationPreferences" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "UserId" uuid NOT NULL,
    "NewRequest" boolean NOT NULL DEFAULT TRUE,
    "RequestAccepted" boolean NOT NULL DEFAULT TRUE,
    "RequestRejected" boolean NOT NULL DEFAULT TRUE,
    "OnTheWay" boolean NOT NULL DEFAULT TRUE,
    "Started" boolean NOT NULL DEFAULT TRUE,
    "Completed" boolean NOT NULL DEFAULT TRUE,
    "Cancelled" boolean NOT NULL DEFAULT TRUE,
    "NewReview" boolean NOT NULL DEFAULT TRUE,
    "CreatedAt" timestamp with time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT "PK_UserNotificationPreferences" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_UserNotificationPreferences_Users_UserId" FOREIGN KEY ("UserId") REFERENCES "Users" ("Id") ON DELETE CASCADE
);

CREATE UNIQUE INDEX "IX_UserNotificationPreferences_UserId" ON "UserNotificationPreferences" ("UserId");

INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion")
VALUES ('20260808120000_AddUserNotificationPreferences', '8.0.11');

COMMIT;

