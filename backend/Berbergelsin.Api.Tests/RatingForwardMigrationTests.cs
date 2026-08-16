using Berbergelsin.Api.Migrations;
using Microsoft.Data.Sqlite;
using Xunit;

namespace Berbergelsin.Api.Tests;

public sealed class RatingForwardMigrationTests
{
    [Fact]
    public async Task Forward_fix_maps_only_zero_preserves_rows_relations_and_is_idempotent()
    {
        await using var connection = new SqliteConnection("Data Source=:memory:");
        await connection.OpenAsync();
        await Execute(connection, """
            CREATE TABLE "Ratings" (
                "Id" TEXT PRIMARY KEY,
                "ModerationStatus" INTEGER NOT NULL,
                "IsDeleted" INTEGER NOT NULL,
                "Comment" TEXT NULL
            );
            CREATE TABLE "RatingReports" (
                "Id" TEXT PRIMARY KEY,
                "RatingId" TEXT NOT NULL REFERENCES "Ratings"("Id")
            );
            CREATE TABLE "RatingBusinessResponses" (
                "Id" TEXT PRIMARY KEY,
                "RatingId" TEXT NOT NULL REFERENCES "Ratings"("Id"),
                "Response" TEXT NOT NULL
            );
            INSERT INTO "Ratings" VALUES
                ('legacy-normal', 0, 0, 'normal'),
                ('legacy-soft-deleted', 0, 1, 'deleted'),
                ('already-visible', 1, 0, 'visible'),
                ('already-under-review', 2, 0, 'review'),
                ('already-hidden', 3, 0, 'hidden'),
                ('reported', 0, 0, 'reported'),
                ('with-business-response', 0, 0, 'response'),
                ('unique-normal-a', 0, 0, 'a'),
                ('unique-normal-b', 0, 0, 'b');
            INSERT INTO "RatingReports" VALUES ('report-1', 'reported');
            INSERT INTO "RatingBusinessResponses" VALUES ('response-1', 'with-business-response', 'preserve me');
            """);

        var beforeCount = await ScalarLong(connection, "SELECT COUNT(*) FROM \"Ratings\"");
        var firstChanged = await Execute(connection, FixLegacyRatingModerationStatus.ForwardFixSql);
        var secondChanged = await Execute(connection, FixLegacyRatingModerationStatus.ForwardFixSql);

        Assert.Equal(6, firstChanged);
        Assert.Equal(0, secondChanged);
        Assert.Equal(beforeCount, await ScalarLong(connection, "SELECT COUNT(*) FROM \"Ratings\""));
        Assert.Equal(0, await ScalarLong(connection, "SELECT COUNT(*) FROM \"Ratings\" WHERE \"ModerationStatus\" = 0"));
        Assert.Equal(1, await ScalarLong(connection, "SELECT \"IsDeleted\" FROM \"Ratings\" WHERE \"Id\" = 'legacy-soft-deleted'"));
        Assert.Equal(2, await ScalarLong(connection, "SELECT \"ModerationStatus\" FROM \"Ratings\" WHERE \"Id\" = 'already-under-review'"));
        Assert.Equal(3, await ScalarLong(connection, "SELECT \"ModerationStatus\" FROM \"Ratings\" WHERE \"Id\" = 'already-hidden'"));
        Assert.Equal(1, await ScalarLong(connection, "SELECT COUNT(*) FROM \"RatingReports\" WHERE \"RatingId\" = 'reported'"));
        Assert.Equal(1, await ScalarLong(connection, "SELECT COUNT(*) FROM \"RatingBusinessResponses\" WHERE \"Response\" = 'preserve me'"));
        Assert.Equal(2, await ScalarLong(connection, "SELECT COUNT(DISTINCT \"Id\") FROM \"Ratings\" WHERE \"Id\" LIKE 'unique-normal-%'"));
    }

    private static async Task<int> Execute(SqliteConnection connection, string sql)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = sql;
        return await command.ExecuteNonQueryAsync();
    }

    private static async Task<long> ScalarLong(SqliteConnection connection, string sql)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = sql;
        return Convert.ToInt64(await command.ExecuteScalarAsync());
    }
}
