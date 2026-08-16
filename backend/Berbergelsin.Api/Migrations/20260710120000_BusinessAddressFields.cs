using Berbergelsin.Api.Data;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Berbergelsin.Api.Migrations
{
    [DbContext(typeof(AppDbContext))]
    [Migration("20260710120000_BusinessAddressFields")]
    public partial class BusinessAddressFields : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "AddressLine",
                table: "BarberProfiles",
                type: "character varying(300)",
                maxLength: 300,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "City",
                table: "BarberProfiles",
                type: "character varying(80)",
                maxLength: 80,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "District",
                table: "BarberProfiles",
                type: "character varying(80)",
                maxLength: 80,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Neighborhood",
                table: "BarberProfiles",
                type: "character varying(120)",
                maxLength: 120,
                nullable: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(name: "AddressLine", table: "BarberProfiles");
            migrationBuilder.DropColumn(name: "City", table: "BarberProfiles");
            migrationBuilder.DropColumn(name: "District", table: "BarberProfiles");
            migrationBuilder.DropColumn(name: "Neighborhood", table: "BarberProfiles");
        }
    }
}
