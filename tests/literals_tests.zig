const std = @import("std");
const testing = std.testing;
const forthic = @import("forthic");
const literals_mod = forthic.literals;

const LiteralValue = literals_mod.LiteralValue;

test "literals: to_bool true" {
    const allocator = testing.allocator;
    const result = try literals_mod.toBool(allocator, "TRUE");
    try testing.expect(result != null);
    try testing.expectEqual(true, result.?.bool_value);
}

test "literals: to_bool false" {
    const allocator = testing.allocator;
    const result = try literals_mod.toBool(allocator, "FALSE");
    try testing.expect(result != null);
    try testing.expectEqual(false, result.?.bool_value);
}

test "literals: to_bool invalid" {
    const allocator = testing.allocator;
    const result1 = try literals_mod.toBool(allocator, "true");
    try testing.expect(result1 == null);

    const result2 = try literals_mod.toBool(allocator, "True");
    try testing.expect(result2 == null);
}

test "literals: to_int positive" {
    const allocator = testing.allocator;
    const result = try literals_mod.toInt(allocator, "42");
    try testing.expect(result != null);
    try testing.expectEqual(@as(i64, 42), result.?.int_value);
}

test "literals: to_int negative" {
    const allocator = testing.allocator;
    const result = try literals_mod.toInt(allocator, "-10");
    try testing.expect(result != null);
    try testing.expectEqual(@as(i64, -10), result.?.int_value);
}

test "literals: to_int zero" {
    const allocator = testing.allocator;
    const result = try literals_mod.toInt(allocator, "0");
    try testing.expect(result != null);
    try testing.expectEqual(@as(i64, 0), result.?.int_value);
}

test "literals: to_int large" {
    const allocator = testing.allocator;
    const result = try literals_mod.toInt(allocator, "1000000");
    try testing.expect(result != null);
    try testing.expectEqual(@as(i64, 1000000), result.?.int_value);
}

test "literals: to_int float should fail" {
    const allocator = testing.allocator;
    const result = try literals_mod.toInt(allocator, "3.14");
    try testing.expect(result == null);
}

test "literals: to_int invalid" {
    const allocator = testing.allocator;
    const result1 = try literals_mod.toInt(allocator, "abc");
    try testing.expect(result1 == null);

    const result2 = try literals_mod.toInt(allocator, "42abc");
    try testing.expect(result2 == null);
}

test "literals: to_float simple" {
    const allocator = testing.allocator;
    const result = try literals_mod.toFloat(allocator, "3.14");
    try testing.expect(result != null);
    try testing.expectApproxEqAbs(@as(f64, 3.14), result.?.float_value, 0.0001);
}

test "literals: to_float negative" {
    const allocator = testing.allocator;
    const result = try literals_mod.toFloat(allocator, "-2.5");
    try testing.expect(result != null);
    try testing.expectApproxEqAbs(@as(f64, -2.5), result.?.float_value, 0.0001);
}

test "literals: to_float zero" {
    const allocator = testing.allocator;
    const result = try literals_mod.toFloat(allocator, "0.0");
    try testing.expect(result != null);
    try testing.expectApproxEqAbs(@as(f64, 0.0), result.?.float_value, 0.0001);
}

test "literals: to_float no decimal should fail" {
    const allocator = testing.allocator;
    const result = try literals_mod.toFloat(allocator, "42");
    try testing.expect(result == null);
}

test "literals: to_float invalid" {
    const allocator = testing.allocator;
    const result = try literals_mod.toFloat(allocator, "abc");
    try testing.expect(result == null);
}

test "literals: to_time simple" {
    const allocator = testing.allocator;
    const result = try literals_mod.toTime(allocator, "9:00");
    try testing.expect(result != null);
    try testing.expectEqual(@as(u8, 9), result.?.time_value.hour);
    try testing.expectEqual(@as(u8, 0), result.?.time_value.minute);
}

test "literals: to_time afternoon" {
    const allocator = testing.allocator;
    const result = try literals_mod.toTime(allocator, "14:30");
    try testing.expect(result != null);
    try testing.expectEqual(@as(u8, 14), result.?.time_value.hour);
    try testing.expectEqual(@as(u8, 30), result.?.time_value.minute);
}

test "literals: to_time PM" {
    const allocator = testing.allocator;
    const result = try literals_mod.toTime(allocator, "2:30 PM");
    try testing.expect(result != null);
    try testing.expectEqual(@as(u8, 14), result.?.time_value.hour);
    try testing.expectEqual(@as(u8, 30), result.?.time_value.minute);
}

test "literals: to_time AM" {
    const allocator = testing.allocator;
    const result = try literals_mod.toTime(allocator, "9:00 AM");
    try testing.expect(result != null);
    try testing.expectEqual(@as(u8, 9), result.?.time_value.hour);
    try testing.expectEqual(@as(u8, 0), result.?.time_value.minute);
}

test "literals: to_time noon" {
    const allocator = testing.allocator;
    const result = try literals_mod.toTime(allocator, "12:00 PM");
    try testing.expect(result != null);
    try testing.expectEqual(@as(u8, 12), result.?.time_value.hour);
    try testing.expectEqual(@as(u8, 0), result.?.time_value.minute);
}

test "literals: to_time midnight" {
    const allocator = testing.allocator;
    const result = try literals_mod.toTime(allocator, "12:00 AM");
    try testing.expect(result != null);
    try testing.expectEqual(@as(u8, 0), result.?.time_value.hour);
    try testing.expectEqual(@as(u8, 0), result.?.time_value.minute);
}

test "literals: to_time invalid" {
    const allocator = testing.allocator;
    const result = try literals_mod.toTime(allocator, "25:00");
    try testing.expect(result == null);
}

test "literals: to_literal_date valid" {
    const allocator = testing.allocator;
    const result = try literals_mod.toLiteralDate(allocator, "2020-06-05");
    try testing.expect(result != null);
    try testing.expectEqual(@as(i32, 2020), result.?.date_value.year);
    try testing.expectEqual(@as(u8, 6), result.?.date_value.month);
    try testing.expectEqual(@as(u8, 5), result.?.date_value.day);
}

test "literals: to_literal_date year wildcard" {
    const allocator = testing.allocator;
    const result = try literals_mod.toLiteralDate(allocator, "YYYY-06-05");
    try testing.expect(result != null);
    // Year will be current year
    try testing.expectEqual(@as(u8, 6), result.?.date_value.month);
    try testing.expectEqual(@as(u8, 5), result.?.date_value.day);
}

test "literals: to_literal_date invalid" {
    const allocator = testing.allocator;
    const result1 = try literals_mod.toLiteralDate(allocator, "2020/06/05");
    try testing.expect(result1 == null);

    const result2 = try literals_mod.toLiteralDate(allocator, "not-a-date");
    try testing.expect(result2 == null);
}

test "literals: to_zoned_datetime UTC" {
    const allocator = testing.allocator;
    const result = try literals_mod.toZonedDateTime(allocator, "2025-05-24T10:15:00Z");
    try testing.expect(result != null);
    try testing.expectEqual(@as(i32, 2025), result.?.datetime_value.year);
    try testing.expectEqual(@as(u8, 5), result.?.datetime_value.month);
    try testing.expectEqual(@as(u8, 24), result.?.datetime_value.day);
    try testing.expectEqual(@as(u8, 10), result.?.datetime_value.hour);
    try testing.expectEqual(@as(u8, 15), result.?.datetime_value.minute);
}

test "literals: to_zoned_datetime plain" {
    const allocator = testing.allocator;
    const result = try literals_mod.toZonedDateTime(allocator, "2025-05-24T10:15:00");
    try testing.expect(result != null);
    try testing.expectEqual(@as(i32, 2025), result.?.datetime_value.year);
}

test "literals: to_zoned_datetime invalid" {
    const allocator = testing.allocator;
    const result1 = try literals_mod.toZonedDateTime(allocator, "not-a-datetime");
    try testing.expect(result1 == null);

    const result2 = try literals_mod.toZonedDateTime(allocator, "2025-05-24 10:15:00");
    try testing.expect(result2 == null);
}
