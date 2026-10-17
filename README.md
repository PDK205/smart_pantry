# Smart Pantry 2.0 🧊✨

Ứng dụng quản lý tủ lạnh thông minh (Flutter) tích hợp **Google Gemini AI**.

## Tính năng

| | Tính năng | Mô tả |
|---|---|---|
| 📸 | **Chụp tủ lạnh bằng AI** | Chụp/chọn tối đa 4 ảnh (tủ lạnh, túi đồ đi chợ, hóa đơn). Gemini Vision nhận diện từng món, ước lượng số lượng, nhóm, nơi cất và **hạn dùng**. Bạn duyệt/sửa rồi thêm hàng loạt. |
| 🧊 | **Quản lý tủ** | Nhóm thực phẩm (rau, thịt, sữa…), vị trí (ngăn mát/đông/tủ bếp), thanh "độ tươi", lọc nhanh, tìm kiếm, vuốt trái/phải để *Dùng hết* / *Bỏ đi*, dùng một phần, hoàn tác. |
| 🍳 | **AI gợi ý món** | Chọn bữa, thời gian, khẩu phần, "ưu tiên đồ sắp hết hạn", "chỉ dùng đồ có sẵn". Mỗi công thức cho biết nguyên liệu có sẵn/còn thiếu, các bước (đánh dấu từng bước), mẹo. |
| ✅ | **Đã nấu xong** | Tự trừ nguyên liệu đã dùng khỏi tủ (chỉnh được lượng). |
| 💚 | **Lưu món yêu thích** | Xem lại công thức đã lưu không cần gọi AI. |
| 🛒 | **Danh sách đi chợ** | Nhập nhanh "2 kg thịt bò, trứng, sữa"; thêm đồ thiếu từ công thức 1 chạm; **AI gợi ý cần mua**; đồ đã mua → "Cất vào tủ" tự đặt hạn dùng. |
| 👨‍🍳 | **Bếp trưởng AI (chat)** | Trò chuyện, trả lời dạng stream, biết rõ tủ lạnh của bạn. Gợi ý câu hỏi nhanh. |
| 📊 | **Thống kê lãng phí** | Tỉ lệ dùng hết vs bỏ đi theo 7/30/365 ngày, món hay bị bỏ phí, phân bố theo nhóm. |
| 🔔 | **Nhắc hạn** | Thông báo trước 3 ngày, 1 ngày và đúng ngày hết hạn (Android/iOS). |
| 🏷️ | **Quét mã vạch** | Tự tra tên sản phẩm qua Open Food Facts. |
| 🌗 | **Giao diện mới** | Material 3, font Be Vietnam Pro, chế độ sáng/tối, hiệu ứng mượt. |

## Chạy project

```bash
cd smart_pantry_demo
flutter pub get
flutter analyze
flutter test
flutter run            # Android/iOS
flutter run -d chrome  # Web
```

Yêu cầu Flutter stable mới (≥ 3.35). Android tối thiểu API 23.

## Kết nối Gemini API

1. Tạo API key tại <https://aistudio.google.com/apikey> (Google AI Studio → **Get API key**).
2. Mở app → ⚙️ **Cài đặt** → dán key → **Kiểm tra**.
3. Chọn model:
   - `gemini-3.5-flash-lite` – nhanh, rẻ
   - `gemini-3.8-flash` – cân bằng (mặc định)
   - `gemini-4-argon` – nhận diện ảnh chính xác nhất

App gọi trực tiếp Gemini REST API (`/v1beta/models/{model}:generateContent`, chat dùng `:streamGenerateContent?alt=sse`), dùng *structured output* (`responseMimeType` + `responseSchema`) để Gemini luôn trả JSON đúng cấu trúc. Ảnh được thu nhỏ còn tối đa 1568px trước khi gửi để nhanh và tiết kiệm token.

> ⚠️ **Bảo mật**: key được lưu trên máy (SharedPreferences) và app gọi API trực tiếp — phù hợp dùng cá nhân/demo.
> Khi phát hành cho người khác, hãy dựng một backend proxy giữ key (ví dụ Cloudflare Worker / Firebase Function chuyển tiếp tới `generativelanguage.googleapis.com`), rồi nhập URL proxy ở **Cài đặt → Nâng cao → API base URL**.

## Cấu trúc mã nguồn

```
lib/
  main.dart                     # load SharedPreferences trước → không nháy màn hình
  src/
    app.dart                    # MaterialApp, theme, cuộn mượt
    core/                       # tiện ích ngày, định dạng số
    data/                       # model: FoodItem, Category, Recipe, ShoppingItem + JsonListStore
    services/
      gemini_service.dart       # REST client Gemini (retry, stream SSE, lỗi tiếng Việt)
      pantry_ai.dart            # prompt + JSON schema: scan ảnh, gợi ý món, đi chợ, chat
      notification_service.dart
      barcode_lookup.dart       # Open Food Facts
    providers/                  # Riverpod: pantry, shopping, recipes, chat, settings
    shared/                     # theme, widget dùng chung
    features/
      home/  pantry/  scan/  recipes/  shopping/  chat/  stats/  settings/
```

## Tối ưu độ mượt
- Ảnh được giải mã đúng kích thước hiển thị (`cacheWidth`) → ít RAM, cuộn mượt.
- Bỏ `File.existsSync()` trong `build` (I/O đồng bộ làm giật khung hình).
- Danh sách dùng `CustomScrollView` + `SliverList`, `RepaintBoundary` cho từng thẻ.
- Lọc/tìm kiếm tính trong provider riêng + debounce 220ms.
- Tab chỉ dựng khi mở lần đầu, giữ trạng thái bằng `IndexedStack`; tab ẩn tắt animation (`TickerMode`).
- Cập nhật UI trước, ghi bộ nhớ sau (optimistic update).
- Xin quyền thông báo sau khi UI đã hiện → mở app nhanh hơn.

## Đã sửa so với bản cũ
- Xóa `lib/.../local/database.dart` (code Drift hỏng, thiếu dependency → `flutter analyze` lỗi).
- Xóa `test/widget_test.dart` (tham chiếu `MyApp` không tồn tại → `flutter test` lỗi).
- Android: bật core library desugaring (bắt buộc cho flutter_local_notifications), thêm receiver giữ lịch nhắc sau khi khởi động lại, bỏ `roundIcon` trỏ tới file không tồn tại, bỏ `usesCleartextTraffic`, bỏ thuộc tính `package` cũ.
- CI: dùng Flutter stable (bản 3.19 cũ không chạy được Dart ≥ 3.4).
- Dữ liệu bản cũ (`foods_v1`) được tự chuyển sang định dạng mới, tự đoán nhóm thực phẩm.
