START TRANSACTION;

DROP INDEX IF EXISTS "IX_Users_FirebaseUid";

DROP INDEX IF EXISTS "IX_Users_PhoneNumber";

CREATE UNIQUE INDEX "IX_Users_Email_Role" ON "Users" ("Email", "Role");

CREATE UNIQUE INDEX "IX_Users_FirebaseUid_Role" ON "Users" ("FirebaseUid", "Role");

CREATE UNIQUE INDEX "IX_Users_PhoneNumber_Role" ON "Users" ("PhoneNumber", "Role");

INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion")
VALUES ('20260724173642_AllowMultipleRolesPerEmailPhone', '8.0.11');

COMMIT;

START TRANSACTION;

DROP INDEX IF EXISTS "IX_OtpCodes_PhoneNumber_Purpose";

ALTER TABLE "OtpCodes" ALTER COLUMN "PhoneNumber" DROP NOT NULL;

ALTER TABLE "OtpCodes" ADD "Email" character varying(200);

CREATE INDEX "IX_OtpCodes_PhoneNumber_Email_Purpose" ON "OtpCodes" ("PhoneNumber", "Email", "Purpose");

INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion")
VALUES ('20260724173801_AddEmailToOtpCode', '8.0.11');

COMMIT;

