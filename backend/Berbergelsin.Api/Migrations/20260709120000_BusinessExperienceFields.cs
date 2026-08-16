using System;
using Berbergelsin.Api.Data;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Berbergelsin.Api.Migrations
{
    /// <inheritdoc />
    [DbContext(typeof(AppDbContext))]
    [Migration("20260709120000_BusinessExperienceFields")]
    public partial class BusinessExperienceFields : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "AcceptsUrgentRequests",
                table: "BarberProfiles",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "Category",
                table: "BarberProfiles",
                type: "character varying(80)",
                maxLength: 80,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Description",
                table: "BarberProfiles",
                type: "character varying(1000)",
                maxLength: 1000,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "ServiceMode",
                table: "BarberProfiles",
                type: "character varying(30)",
                maxLength: 30,
                nullable: false,
                defaultValue: "Mobile");

            migrationBuilder.AddColumn<string>(
                name: "Description",
                table: "BarberServices",
                type: "character varying(500)",
                maxLength: 500,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "DurationMinutes",
                table: "BarberServices",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "IsPopular",
                table: "BarberServices",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "PriceType",
                table: "BarberServices",
                type: "character varying(20)",
                maxLength: 20,
                nullable: false,
                defaultValue: "Fixed");

            migrationBuilder.CreateTable(
                name: "BusinessPhotos",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    BarberProfileId = table.Column<Guid>(type: "uuid", nullable: false),
                    StoredFileName = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    OriginalFileName = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: false),
                    ContentType = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    SizeBytes = table.Column<long>(type: "bigint", nullable: false),
                    Caption = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: true),
                    IsCover = table.Column<bool>(type: "boolean", nullable: false),
                    SortOrder = table.Column<int>(type: "integer", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_BusinessPhotos", x => x.Id);
                    table.ForeignKey(
                        name: "FK_BusinessPhotos_BarberProfiles_BarberProfileId",
                        column: x => x.BarberProfileId,
                        principalTable: "BarberProfiles",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_BusinessPhotos_BarberProfileId_SortOrder",
                table: "BusinessPhotos",
                columns: new[] { "BarberProfileId", "SortOrder" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "BusinessPhotos");

            migrationBuilder.DropColumn(
                name: "AcceptsUrgentRequests",
                table: "BarberProfiles");

            migrationBuilder.DropColumn(
                name: "Category",
                table: "BarberProfiles");

            migrationBuilder.DropColumn(
                name: "Description",
                table: "BarberProfiles");

            migrationBuilder.DropColumn(
                name: "ServiceMode",
                table: "BarberProfiles");

            migrationBuilder.DropColumn(
                name: "Description",
                table: "BarberServices");

            migrationBuilder.DropColumn(
                name: "DurationMinutes",
                table: "BarberServices");

            migrationBuilder.DropColumn(
                name: "IsPopular",
                table: "BarberServices");

            migrationBuilder.DropColumn(
                name: "PriceType",
                table: "BarberServices");
        }
    }
}
