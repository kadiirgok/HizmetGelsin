using System;
using Microsoft.EntityFrameworkCore.Migrations;
using NetTopologySuite.Geometries;

#nullable disable

namespace Berbergelsin.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddRequestIdempotencyAndConcurrency : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_ServiceRequests_BarberProfileId",
                table: "ServiceRequests");

            migrationBuilder.DropIndex(
                name: "IX_ServiceRequests_ClientUserId",
                table: "ServiceRequests");

            migrationBuilder.AlterColumn<Point>(
                name: "ClientLocation",
                table: "ServiceRequests",
                type: "geography (point, 4326)",
                nullable: true,
                oldClrType: typeof(Point),
                oldType: "geography (point, 4326)");

            migrationBuilder.AddColumn<Guid>(
                name: "CreatedBy",
                table: "ServiceRequests",
                type: "uuid",
                nullable: false,
                defaultValue: new Guid("00000000-0000-0000-0000-000000000000"));

            migrationBuilder.AddColumn<string>(
                name: "IdempotencyKey",
                table: "ServiceRequests",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "IdempotencyPayloadHash",
                table: "ServiceRequests",
                type: "character varying(64)",
                maxLength: 64,
                nullable: true);

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "ScheduledEndTime",
                table: "ServiceRequests",
                type: "timestamp with time zone",
                nullable: false,
                defaultValue: new DateTimeOffset(new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)));

            migrationBuilder.AddColumn<DateTime>(
                name: "UpdatedAt",
                table: "ServiceRequests",
                type: "timestamp with time zone",
                nullable: false,
                defaultValue: new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified));

            // Mevcut geçmişi bozmadan audit ve kaba süre alanlarını güvenli değerlerle doldur.
            migrationBuilder.Sql("""
                UPDATE "ServiceRequests"
                SET "CreatedBy" = "ClientUserId",
                    "UpdatedAt" = "CreatedAt",
                    "ScheduledEndTime" = "RequestedTime" + INTERVAL '1 hour';
                """);

            migrationBuilder.CreateIndex(
                name: "IX_ServiceRequests_BarberProfileId_RequestedTime_ScheduledEndT~",
                table: "ServiceRequests",
                columns: new[] { "BarberProfileId", "RequestedTime", "ScheduledEndTime" });

            migrationBuilder.CreateIndex(
                name: "IX_ServiceRequests_ClientUserId_IdempotencyKey",
                table: "ServiceRequests",
                columns: new[] { "ClientUserId", "IdempotencyKey" },
                unique: true,
                filter: "\"IdempotencyKey\" IS NOT NULL");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_ServiceRequests_BarberProfileId_RequestedTime_ScheduledEndT~",
                table: "ServiceRequests");

            migrationBuilder.DropIndex(
                name: "IX_ServiceRequests_ClientUserId_IdempotencyKey",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "CreatedBy",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "IdempotencyKey",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "IdempotencyPayloadHash",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "ScheduledEndTime",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "UpdatedAt",
                table: "ServiceRequests");

            migrationBuilder.AlterColumn<Point>(
                name: "ClientLocation",
                table: "ServiceRequests",
                type: "geography (point, 4326)",
                nullable: false,
                oldClrType: typeof(Point),
                oldType: "geography (point, 4326)",
                oldNullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_ServiceRequests_BarberProfileId",
                table: "ServiceRequests",
                column: "BarberProfileId");

            migrationBuilder.CreateIndex(
                name: "IX_ServiceRequests_ClientUserId",
                table: "ServiceRequests",
                column: "ClientUserId");
        }
    }
}
