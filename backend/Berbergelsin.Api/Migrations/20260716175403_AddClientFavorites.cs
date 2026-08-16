using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Berbergelsin.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddClientFavorites : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "ClientFavorites",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    BarberProfileId = table.Column<Guid>(type: "uuid", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    Version = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ClientFavorites", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ClientFavorites_BarberProfiles_BarberProfileId",
                        column: x => x.BarberProfileId,
                        principalTable: "BarberProfiles",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_ClientFavorites_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ClientFavorites_BarberProfileId",
                table: "ClientFavorites",
                column: "BarberProfileId");

            migrationBuilder.CreateIndex(
                name: "IX_ClientFavorites_UserId_BarberProfileId",
                table: "ClientFavorites",
                columns: new[] { "UserId", "BarberProfileId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_ClientFavorites_UserId_IsDeleted_CreatedAt",
                table: "ClientFavorites",
                columns: new[] { "UserId", "IsDeleted", "CreatedAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ClientFavorites");
        }
    }
}
