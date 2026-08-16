using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Berbergelsin.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddRequestAddressReference : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "AddressSnapshot",
                table: "ServiceRequests",
                type: "character varying(500)",
                maxLength: 500,
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "ClientAddressId",
                table: "ServiceRequests",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_ServiceRequests_ClientAddressId",
                table: "ServiceRequests",
                column: "ClientAddressId");

            migrationBuilder.AddForeignKey(
                name: "FK_ServiceRequests_ClientAddresses_ClientAddressId",
                table: "ServiceRequests",
                column: "ClientAddressId",
                principalTable: "ClientAddresses",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_ServiceRequests_ClientAddresses_ClientAddressId",
                table: "ServiceRequests");

            migrationBuilder.DropIndex(
                name: "IX_ServiceRequests_ClientAddressId",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "AddressSnapshot",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "ClientAddressId",
                table: "ServiceRequests");
        }
    }
}
