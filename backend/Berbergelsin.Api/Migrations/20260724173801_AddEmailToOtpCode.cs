using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Berbergelsin.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddEmailToOtpCode : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_OtpCodes_PhoneNumber_Purpose",
                table: "OtpCodes");

            migrationBuilder.AlterColumn<string>(
                name: "PhoneNumber",
                table: "OtpCodes",
                type: "character varying(15)",
                maxLength: 15,
                nullable: true,
                oldClrType: typeof(string),
                oldType: "character varying(15)",
                oldMaxLength: 15);

            migrationBuilder.AddColumn<string>(
                name: "Email",
                table: "OtpCodes",
                type: "character varying(200)",
                maxLength: 200,
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_OtpCodes_PhoneNumber_Email_Purpose",
                table: "OtpCodes",
                columns: new[] { "PhoneNumber", "Email", "Purpose" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_OtpCodes_PhoneNumber_Email_Purpose",
                table: "OtpCodes");

            migrationBuilder.DropColumn(
                name: "Email",
                table: "OtpCodes");

            migrationBuilder.AlterColumn<string>(
                name: "PhoneNumber",
                table: "OtpCodes",
                type: "character varying(15)",
                maxLength: 15,
                nullable: false,
                defaultValue: "",
                oldClrType: typeof(string),
                oldType: "character varying(15)",
                oldMaxLength: 15,
                oldNullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_OtpCodes_PhoneNumber_Purpose",
                table: "OtpCodes",
                columns: new[] { "PhoneNumber", "Purpose" });
        }
    }
}
