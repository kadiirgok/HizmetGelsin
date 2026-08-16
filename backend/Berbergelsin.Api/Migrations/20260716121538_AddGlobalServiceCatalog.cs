using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Berbergelsin.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddGlobalServiceCatalog : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "ServiceDefinitionId",
                table: "BarberServices",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "ServiceDefinitions",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: false),
                    NormalizedName = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: false),
                    CategoryName = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    NormalizedCategoryName = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    SortOrder = table.Column<int>(type: "integer", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ServiceDefinitions", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_BarberServices_ServiceDefinitionId",
                table: "BarberServices",
                column: "ServiceDefinitionId");

            migrationBuilder.CreateIndex(
                name: "IX_ServiceDefinitions_IsActive_SortOrder_Name",
                table: "ServiceDefinitions",
                columns: new[] { "IsActive", "SortOrder", "Name" });

            migrationBuilder.CreateIndex(
                name: "IX_ServiceDefinitions_NormalizedCategoryName_NormalizedName",
                table: "ServiceDefinitions",
                columns: new[] { "NormalizedCategoryName", "NormalizedName" },
                unique: true);

            migrationBuilder.AddForeignKey(
                name: "FK_BarberServices_ServiceDefinitions_ServiceDefinitionId",
                table: "BarberServices",
                column: "ServiceDefinitionId",
                principalTable: "ServiceDefinitions",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_BarberServices_ServiceDefinitions_ServiceDefinitionId",
                table: "BarberServices");

            migrationBuilder.DropTable(
                name: "ServiceDefinitions");

            migrationBuilder.DropIndex(
                name: "IX_BarberServices_ServiceDefinitionId",
                table: "BarberServices");

            migrationBuilder.DropColumn(
                name: "ServiceDefinitionId",
                table: "BarberServices");
        }
    }
}
