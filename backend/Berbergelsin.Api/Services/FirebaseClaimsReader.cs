using System.Text.Json;
using Newtonsoft.Json.Linq;

namespace Berbergelsin.Api.Services;

public static class FirebaseClaimsReader
{
    public static string? ExtractSignInProvider(IReadOnlyDictionary<string, object>? claims)
    {
        if (claims == null) return null;

        if (!claims.TryGetValue("firebase", out var firebaseObj) || firebaseObj == null)
        {
            return null;
        }

        return ExtractPropertyAsString(firebaseObj, "sign_in_provider");
    }

    public static string? ExtractEmail(IReadOnlyDictionary<string, object>? claims)
    {
        if (claims == null) return null;
        if (!claims.TryGetValue("email", out var emailObj) || emailObj == null) return null;
        return GetValueAsString(emailObj);
    }

    public static string? ExtractPhoneNumber(IReadOnlyDictionary<string, object>? claims)
    {
        if (claims == null) return null;
        if (!claims.TryGetValue("phone_number", out var phoneObj) || phoneObj == null) return null;
        return GetValueAsString(phoneObj);
    }

    public static bool ExtractEmailVerified(IReadOnlyDictionary<string, object>? claims)
    {
        if (claims == null) return false;
        if (!claims.TryGetValue("email_verified", out var evObj) || evObj == null) return false;

        if (evObj is bool b) return b;

        var str = GetValueAsString(evObj);
        if (str != null && bool.TryParse(str, out var parsed))
        {
            return parsed;
        }

        if (evObj is JsonElement elem)
        {
            if (elem.ValueKind == JsonValueKind.True) return true;
            if (elem.ValueKind == JsonValueKind.False) return false;
            if (elem.ValueKind == JsonValueKind.String && bool.TryParse(elem.GetString(), out var p)) return p;
        }

        if (evObj is JToken token)
        {
            if (token.Type == JTokenType.Boolean) return token.Value<bool>();
            if (token.Type == JTokenType.String && bool.TryParse(token.Value<string>(), out var p)) return p;
        }

        return false;
    }

    private static string? ExtractPropertyAsString(object container, string propertyName)
    {
        if (container is JsonElement jsonElem)
        {
            if (jsonElem.ValueKind == JsonValueKind.Object && jsonElem.TryGetProperty(propertyName, out var propElem))
            {
                return GetValueAsString(propElem);
            }
            return null;
        }

        if (container is JObject jObj)
        {
            if (jObj.TryGetValue(propertyName, StringComparison.OrdinalIgnoreCase, out var token))
            {
                return GetValueAsString(token);
            }
            return null;
        }

        if (container is JToken jToken && jToken.Type == JTokenType.Object)
        {
            var childToken = jToken[propertyName];
            if (childToken != null) return GetValueAsString(childToken);
            return null;
        }

        if (container is IDictionary<string, object> dict)
        {
            if (dict.TryGetValue(propertyName, out var val))
            {
                return GetValueAsString(val);
            }
            foreach (var kvp in dict)
            {
                if (string.Equals(kvp.Key, propertyName, StringComparison.OrdinalIgnoreCase))
                {
                    return GetValueAsString(kvp.Value);
                }
            }
            return null;
        }

        if (container is IReadOnlyDictionary<string, object> roDict)
        {
            if (roDict.TryGetValue(propertyName, out var val))
            {
                return GetValueAsString(val);
            }
            foreach (var kvp in roDict)
            {
                if (string.Equals(kvp.Key, propertyName, StringComparison.OrdinalIgnoreCase))
                {
                    return GetValueAsString(kvp.Value);
                }
            }
            return null;
        }

        return null;
    }

    private static string? GetValueAsString(object? val)
    {
        if (val == null) return null;
        if (val is string s) return s;
        if (val is JsonElement elem)
        {
            return elem.ValueKind switch
            {
                JsonValueKind.String => elem.GetString(),
                _ => elem.ToString()
            };
        }
        if (val is JToken jToken)
        {
            return jToken.Type switch
            {
                JTokenType.String => jToken.Value<string>(),
                JTokenType.Null or JTokenType.Undefined => null,
                _ => jToken.ToString()
            };
        }
        return val.ToString();
    }
}
