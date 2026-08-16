using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Berbergelsin.Api.Migrations
{
    /// <inheritdoc />
    public partial class FixLegacyRatingModerationStatus : Migration
    {
        public const string ForwardFixSql = """
            UPDATE "Ratings"
            SET "ModerationStatus" = 1
            WHERE "ModerationStatus" = 0;
            """;

        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(ForwardFixSql);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Intentionally empty. Moderation history cannot be reconstructed safely;
            // operational recovery is a forward-fix, never a status downgrade.
        }
    }
}
