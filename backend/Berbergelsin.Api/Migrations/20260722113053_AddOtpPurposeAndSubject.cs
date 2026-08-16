using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Berbergelsin.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddOtpPurposeAndSubject : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_OtpCodes_PhoneNumber",
                table: "OtpCodes");

            migrationBuilder.AddColumn<int>(
                name: "Purpose",
                table: "OtpCodes",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "Subject",
                table: "OtpCodes",
                type: "character varying(128)",
                maxLength: 128,
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_OtpCodes_PhoneNumber_Purpose",
                table: "OtpCodes",
                columns: new[] { "PhoneNumber", "Purpose" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_OtpCodes_PhoneNumber_Purpose",
                table: "OtpCodes");

            migrationBuilder.DropColumn(
                name: "Purpose",
                table: "OtpCodes");

            migrationBuilder.DropColumn(
                name: "Subject",
                table: "OtpCodes");

            migrationBuilder.CreateIndex(
                name: "IX_OtpCodes_PhoneNumber",
                table: "OtpCodes",
                column: "PhoneNumber");
        }
    }
}
