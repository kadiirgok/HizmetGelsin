using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Berbergelsin.Api.Migrations
{
    /// <inheritdoc />
    public partial class AllowMultipleRolesPerEmailPhone : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Users_FirebaseUid",
                table: "Users");

            migrationBuilder.DropIndex(
                name: "IX_Users_PhoneNumber",
                table: "Users");

            migrationBuilder.CreateIndex(
                name: "IX_Users_Email_Role",
                table: "Users",
                columns: new[] { "Email", "Role" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Users_FirebaseUid_Role",
                table: "Users",
                columns: new[] { "FirebaseUid", "Role" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Users_PhoneNumber_Role",
                table: "Users",
                columns: new[] { "PhoneNumber", "Role" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Users_Email_Role",
                table: "Users");

            migrationBuilder.DropIndex(
                name: "IX_Users_FirebaseUid_Role",
                table: "Users");

            migrationBuilder.DropIndex(
                name: "IX_Users_PhoneNumber_Role",
                table: "Users");

            migrationBuilder.CreateIndex(
                name: "IX_Users_FirebaseUid",
                table: "Users",
                column: "FirebaseUid",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Users_PhoneNumber",
                table: "Users",
                column: "PhoneNumber",
                unique: true);
        }
    }
}
