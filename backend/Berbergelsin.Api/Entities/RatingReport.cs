namespace Berbergelsin.Api.Entities;
public sealed class RatingReport{public Guid Id{get;set;}public Guid RatingId{get;set;}public Rating Rating{get;set;}=null!;public Guid ReporterUserId{get;set;}public string ReasonCode{get;set;}=null!;public string? Description{get;set;}public DateTime CreatedAt{get;set;}}
