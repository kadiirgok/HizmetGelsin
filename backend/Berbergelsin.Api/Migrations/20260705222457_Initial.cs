using System;
using Microsoft.EntityFrameworkCore.Migrations;
using NetTopologySuite.Geometries;

#nullable disable

namespace Berbergelsin.Api.Migrations
{
    /// <inheritdoc />
    public partial class Initial : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterDatabase()
                .Annotation("Npgsql:PostgresExtension:postgis", ",,");

            migrationBuilder.CreateTable(
                name: "OtpCodes",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    PhoneNumber = table.Column<string>(type: "character varying(15)", maxLength: 15, nullable: false),
                    CodeHash = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    ExpiresAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    AttemptCount = table.Column<int>(type: "integer", nullable: false),
                    Consumed = table.Column<bool>(type: "boolean", nullable: false),
                    RequestIp = table.Column<string>(type: "text", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_OtpCodes", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Users",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    PhoneNumber = table.Column<string>(type: "character varying(15)", maxLength: 15, nullable: false),
                    Role = table.Column<int>(type: "integer", nullable: false),
                    FirstName = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    LastName = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    Email = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    KvkkAcceptedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    OnboardingCompleted = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Users", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "BarberProfiles",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    BusinessName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    TcKimlikNo = table.Column<string>(type: "character varying(11)", maxLength: 11, nullable: true),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    RejectionReason = table.Column<string>(type: "text", nullable: true),
                    SharePhone = table.Column<bool>(type: "boolean", nullable: false),
                    AcceptsOffers = table.Column<bool>(type: "boolean", nullable: false),
                    ServiceRadiusKm = table.Column<int>(type: "integer", nullable: false),
                    Location = table.Column<Point>(type: "geography (point, 4326)", nullable: true),
                    IsOnline = table.Column<bool>(type: "boolean", nullable: false),
                    LastLocationAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    WorkingHours = table.Column<string>(type: "jsonb", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    ApprovedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_BarberProfiles", x => x.Id);
                    table.ForeignKey(
                        name: "FK_BarberProfiles_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "RefreshTokens",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    TokenHash = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    ExpiresAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    CreatedByIp = table.Column<string>(type: "text", nullable: true),
                    RevokedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    ReplacedByTokenHash = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_RefreshTokens", x => x.Id);
                    table.ForeignKey(
                        name: "FK_RefreshTokens_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "BarberDocuments",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    BarberProfileId = table.Column<Guid>(type: "uuid", nullable: false),
                    Type = table.Column<int>(type: "integer", nullable: false),
                    StoredFileName = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    OriginalFileName = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: false),
                    ContentType = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    SizeBytes = table.Column<long>(type: "bigint", nullable: false),
                    UploadedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_BarberDocuments", x => x.Id);
                    table.ForeignKey(
                        name: "FK_BarberDocuments_BarberProfiles_BarberProfileId",
                        column: x => x.BarberProfileId,
                        principalTable: "BarberProfiles",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "BarberServices",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    BarberProfileId = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: false),
                    Price = table.Column<decimal>(type: "numeric(10,2)", nullable: false),
                    SortOrder = table.Column<int>(type: "integer", nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_BarberServices", x => x.Id);
                    table.ForeignKey(
                        name: "FK_BarberServices_BarberProfiles_BarberProfileId",
                        column: x => x.BarberProfileId,
                        principalTable: "BarberProfiles",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "PriceOffers",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ClientUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    BarberProfileId = table.Column<Guid>(type: "uuid", nullable: false),
                    ProposedPrice = table.Column<decimal>(type: "numeric(10,2)", nullable: false),
                    CounterPrice = table.Column<decimal>(type: "numeric(10,2)", nullable: true),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    Note = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    RequestedTime = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    ClientLocation = table.Column<Point>(type: "geography (point, 4326)", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    RespondedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PriceOffers", x => x.Id);
                    table.ForeignKey(
                        name: "FK_PriceOffers_BarberProfiles_BarberProfileId",
                        column: x => x.BarberProfileId,
                        principalTable: "BarberProfiles",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_PriceOffers_Users_ClientUserId",
                        column: x => x.ClientUserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "ServiceRequests",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ClientUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    BarberProfileId = table.Column<Guid>(type: "uuid", nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    RequestedTime = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    ClientLocation = table.Column<Point>(type: "geography (point, 4326)", nullable: false),
                    AddressNote = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    TotalPrice = table.Column<decimal>(type: "numeric(10,2)", nullable: false),
                    OriginPriceOfferId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    RespondedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CompletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CancelledAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ServiceRequests", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ServiceRequests_BarberProfiles_BarberProfileId",
                        column: x => x.BarberProfileId,
                        principalTable: "BarberProfiles",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ServiceRequests_PriceOffers_OriginPriceOfferId",
                        column: x => x.OriginPriceOfferId,
                        principalTable: "PriceOffers",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_ServiceRequests_Users_ClientUserId",
                        column: x => x.ClientUserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "ServiceRequestItems",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ServiceRequestId = table.Column<Guid>(type: "uuid", nullable: false),
                    BarberServiceId = table.Column<Guid>(type: "uuid", nullable: false),
                    ServiceName = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: false),
                    PriceAtRequest = table.Column<decimal>(type: "numeric(10,2)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ServiceRequestItems", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ServiceRequestItems_ServiceRequests_ServiceRequestId",
                        column: x => x.ServiceRequestId,
                        principalTable: "ServiceRequests",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_BarberDocuments_BarberProfileId",
                table: "BarberDocuments",
                column: "BarberProfileId");

            migrationBuilder.CreateIndex(
                name: "IX_BarberProfiles_Location",
                table: "BarberProfiles",
                column: "Location")
                .Annotation("Npgsql:IndexMethod", "gist");

            migrationBuilder.CreateIndex(
                name: "IX_BarberProfiles_UserId",
                table: "BarberProfiles",
                column: "UserId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_BarberServices_BarberProfileId",
                table: "BarberServices",
                column: "BarberProfileId");

            migrationBuilder.CreateIndex(
                name: "IX_OtpCodes_PhoneNumber",
                table: "OtpCodes",
                column: "PhoneNumber");

            migrationBuilder.CreateIndex(
                name: "IX_PriceOffers_BarberProfileId",
                table: "PriceOffers",
                column: "BarberProfileId");

            migrationBuilder.CreateIndex(
                name: "IX_PriceOffers_ClientUserId",
                table: "PriceOffers",
                column: "ClientUserId");

            migrationBuilder.CreateIndex(
                name: "IX_RefreshTokens_TokenHash",
                table: "RefreshTokens",
                column: "TokenHash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_RefreshTokens_UserId",
                table: "RefreshTokens",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_ServiceRequestItems_ServiceRequestId",
                table: "ServiceRequestItems",
                column: "ServiceRequestId");

            migrationBuilder.CreateIndex(
                name: "IX_ServiceRequests_BarberProfileId",
                table: "ServiceRequests",
                column: "BarberProfileId");

            migrationBuilder.CreateIndex(
                name: "IX_ServiceRequests_ClientUserId",
                table: "ServiceRequests",
                column: "ClientUserId");

            migrationBuilder.CreateIndex(
                name: "IX_ServiceRequests_OriginPriceOfferId",
                table: "ServiceRequests",
                column: "OriginPriceOfferId");

            migrationBuilder.CreateIndex(
                name: "IX_Users_PhoneNumber",
                table: "Users",
                column: "PhoneNumber",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "BarberDocuments");

            migrationBuilder.DropTable(
                name: "BarberServices");

            migrationBuilder.DropTable(
                name: "OtpCodes");

            migrationBuilder.DropTable(
                name: "RefreshTokens");

            migrationBuilder.DropTable(
                name: "ServiceRequestItems");

            migrationBuilder.DropTable(
                name: "ServiceRequests");

            migrationBuilder.DropTable(
                name: "PriceOffers");

            migrationBuilder.DropTable(
                name: "BarberProfiles");

            migrationBuilder.DropTable(
                name: "Users");
        }
    }
}
