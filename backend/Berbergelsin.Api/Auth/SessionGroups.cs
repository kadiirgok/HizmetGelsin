namespace Berbergelsin.Api.Auth;

public static class SessionGroups
{
    public static string User(Guid userId, int tokenVersion) => $"user:{userId}:v{tokenVersion}";
}
