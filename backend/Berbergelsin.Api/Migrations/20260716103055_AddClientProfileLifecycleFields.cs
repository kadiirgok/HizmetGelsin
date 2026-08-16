using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Berbergelsin.Api.Migrations
{
    public partial class AddClientProfileLifecycleFields : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "AccountStatus",
                table: "Users",
                type: "integer",
                nullable: false,
                defaultValue: 1);

            migrationBuilder.AddColumn<DateTime>(
                name: "DeletionRequestedAt",
                table: "Users",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "IsPhoneVerified",
                table: "Users",
                type: "boolean",
                nullable: false,
                defaultValue: true);

            migrationBuilder.AddColumn<string>(
                name: "ProfileImageUrl",
                table: "Users",
                type: "character varying(2048)",
                maxLength: 2048,
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "ProfileVersion",
                table: "Users",
                type: "uuid",
                nullable: false,
                defaultValue: Guid.Empty);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(name: "AccountStatus", table: "Users");
            migrationBuilder.DropColumn(name: "DeletionRequestedAt", table: "Users");
            migrationBuilder.DropColumn(name: "IsPhoneVerified", table: "Users");
            migrationBuilder.DropColumn(name: "ProfileImageUrl", table: "Users");
            migrationBuilder.DropColumn(name: "ProfileVersion", table: "Users");
        }
    }
}
