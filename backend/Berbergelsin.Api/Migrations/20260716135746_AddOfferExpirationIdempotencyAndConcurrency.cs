using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Berbergelsin.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddOfferExpirationIdempotencyAndConcurrency : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_PriceOffers_ClientUserId",
                table: "PriceOffers");

            migrationBuilder.AddColumn<decimal>(
                name: "AcceptedPrice",
                table: "PriceOffers",
                type: "numeric(10,2)",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "ExpiresAt",
                table: "PriceOffers",
                type: "timestamp with time zone",
                nullable: false,
                defaultValue: new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified));

            migrationBuilder.AddColumn<Guid>(
                name: "SourceServiceRequestId",
                table: "PriceOffers",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "Version",
                table: "PriceOffers",
                type: "uuid",
                nullable: false,
                defaultValue: new Guid("00000000-0000-0000-0000-000000000000"));

            migrationBuilder.Sql("""
                UPDATE "PriceOffers"
                SET "ExpiresAt" = "CreatedAt" + INTERVAL '24 hours',
                    "AcceptedPrice" = CASE
                        WHEN "Status" = 2 THEN "ProposedPrice"
                        WHEN "Status" = 5 THEN "CounterPrice"
                        ELSE NULL
                    END;
                """);

            migrationBuilder.CreateTable(
                name: "OfferOperations",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    IdempotencyKey = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    PayloadHash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    ResultJson = table.Column<string>(type: "jsonb", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_OfferOperations", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_PriceOffers_ClientUserId_BarberProfileId_Status",
                table: "PriceOffers",
                columns: new[] { "ClientUserId", "BarberProfileId", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_PriceOffers_SourceServiceRequestId",
                table: "PriceOffers",
                column: "SourceServiceRequestId");

            migrationBuilder.CreateIndex(
                name: "IX_OfferOperations_UserId_IdempotencyKey",
                table: "OfferOperations",
                columns: new[] { "UserId", "IdempotencyKey" },
                unique: true);

            migrationBuilder.AddForeignKey(
                name: "FK_PriceOffers_ServiceRequests_SourceServiceRequestId",
                table: "PriceOffers",
                column: "SourceServiceRequestId",
                principalTable: "ServiceRequests",
                principalColumn: "Id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_PriceOffers_ServiceRequests_SourceServiceRequestId",
                table: "PriceOffers");

            migrationBuilder.DropTable(
                name: "OfferOperations");

            migrationBuilder.DropIndex(
                name: "IX_PriceOffers_ClientUserId_BarberProfileId_Status",
                table: "PriceOffers");

            migrationBuilder.DropIndex(
                name: "IX_PriceOffers_SourceServiceRequestId",
                table: "PriceOffers");

            migrationBuilder.DropColumn(
                name: "AcceptedPrice",
                table: "PriceOffers");

            migrationBuilder.DropColumn(
                name: "ExpiresAt",
                table: "PriceOffers");

            migrationBuilder.DropColumn(
                name: "SourceServiceRequestId",
                table: "PriceOffers");

            migrationBuilder.DropColumn(
                name: "Version",
                table: "PriceOffers");

            migrationBuilder.CreateIndex(
                name: "IX_PriceOffers_ClientUserId",
                table: "PriceOffers",
                column: "ClientUserId");
        }
    }
}
