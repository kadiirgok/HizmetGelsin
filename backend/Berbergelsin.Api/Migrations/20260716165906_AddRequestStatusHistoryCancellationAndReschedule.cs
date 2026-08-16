using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Berbergelsin.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddRequestStatusHistoryCancellationAndReschedule : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "CancellationReasonCode",
                table: "ServiceRequests",
                type: "character varying(50)",
                maxLength: 50,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "CancellationReasonText",
                table: "ServiceRequests",
                type: "character varying(500)",
                maxLength: 500,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "CancelledByRole",
                table: "ServiceRequests",
                type: "character varying(20)",
                maxLength: 20,
                nullable: true);

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "PreviousRequestedTime",
                table: "ServiceRequests",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "ProposedStartAt",
                table: "ServiceRequests",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "RescheduleRequestedByRole",
                table: "ServiceRequests",
                type: "character varying(20)",
                maxLength: 20,
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "Version",
                table: "ServiceRequests",
                type: "uuid",
                nullable: false,
                defaultValue: new Guid("00000000-0000-0000-0000-000000000000"));

            migrationBuilder.CreateTable(
                name: "RequestOperations",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    IdempotencyKey = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    PayloadHash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    RequestId = table.Column<Guid>(type: "uuid", nullable: false),
                    ResultJson = table.Column<string>(type: "jsonb", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_RequestOperations", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "RequestStatusHistories",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    RequestId = table.Column<Guid>(type: "uuid", nullable: false),
                    FromStatus = table.Column<int>(type: "integer", nullable: false),
                    ToStatus = table.Column<int>(type: "integer", nullable: false),
                    ChangedByUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    ChangedByRole = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    ReasonCode = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    ReasonText = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_RequestStatusHistories", x => x.Id);
                    table.ForeignKey(
                        name: "FK_RequestStatusHistories_ServiceRequests_RequestId",
                        column: x => x.RequestId,
                        principalTable: "ServiceRequests",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_RequestOperations_UserId_IdempotencyKey",
                table: "RequestOperations",
                columns: new[] { "UserId", "IdempotencyKey" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_RequestStatusHistories_RequestId_CreatedAt_Id",
                table: "RequestStatusHistories",
                columns: new[] { "RequestId", "CreatedAt", "Id" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "RequestOperations");

            migrationBuilder.DropTable(
                name: "RequestStatusHistories");

            migrationBuilder.DropColumn(
                name: "CancellationReasonCode",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "CancellationReasonText",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "CancelledByRole",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "PreviousRequestedTime",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "ProposedStartAt",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "RescheduleRequestedByRole",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "Version",
                table: "ServiceRequests");
        }
    }
}
