#include "flutter_window.h"

#include <algorithm>
#include <commdlg.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {

struct ChallanPrintItem {
  std::wstring particulars;
  std::wstring hsn_code;
  std::wstring quantity_pcs;
  std::wstring weight;
};

struct ChallanPrintData {
  std::wstring doc_title;
  std::wstring company_name;
  std::wstring mobile;
  std::wstring business_description;
  std::wstring address;
  std::wstring party_label;
  std::wstring party_name;
  std::wstring party_gstin;
  std::wstring location;
  std::wstring reference_label;
  std::wstring reference_value;
  std::wstring challan_no;
  std::wstring date;
  std::wstring state_code;
  std::wstring gstin;
  std::wstring signature_label;
  std::vector<ChallanPrintItem> items;
};

struct SelectedPrinter {
  std::wstring name;
  std::wstring driver;
  std::wstring port;
};

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return L"";
  }

  const int size = ::MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                         static_cast<int>(value.size()),
                                         nullptr, 0);
  if (size <= 0) {
    return L"";
  }

  std::wstring result(size, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                        static_cast<int>(value.size()), result.data(), size);
  return result;
}

std::wstring GetString(const flutter::EncodableMap& map, const char* key) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return L"";
  }

  const auto value = std::get_if<std::string>(&it->second);
  return value == nullptr ? L"" : Utf8ToWide(*value);
}

std::wstring GetArgumentString(const flutter::EncodableValue* arguments,
                               const char* key) {
  const auto map = std::get_if<flutter::EncodableMap>(arguments);
  if (map == nullptr) {
    return L"";
  }
  return GetString(*map, key);
}

ChallanPrintData PrintDataFromArguments(
    const flutter::EncodableValue* arguments) {
  ChallanPrintData data;
  const auto map = std::get_if<flutter::EncodableMap>(arguments);
  if (map == nullptr) {
    return data;
  }

  data.doc_title = GetString(*map, "docTitle");
  data.company_name = GetString(*map, "companyName");
  data.mobile = GetString(*map, "mobile");
  data.business_description = GetString(*map, "businessDescription");
  data.address = GetString(*map, "address");
  data.party_label = GetString(*map, "partyLabel");
  data.party_name = GetString(*map, "partyName");
  data.party_gstin = GetString(*map, "partyGstin");
  data.location = GetString(*map, "location");
  data.reference_label = GetString(*map, "referenceLabel");
  data.reference_value = GetString(*map, "referenceValue");
  data.challan_no = GetString(*map, "challanNo");
  data.date = GetString(*map, "date");
  data.state_code = GetString(*map, "stateCode");
  data.gstin = GetString(*map, "gstin");
  data.signature_label = GetString(*map, "signatureLabel");

  const auto items_it = map->find(flutter::EncodableValue("items"));
  if (items_it != map->end()) {
    const auto items = std::get_if<flutter::EncodableList>(&items_it->second);
    if (items != nullptr) {
      for (const auto& item_value : *items) {
        const auto item_map =
            std::get_if<flutter::EncodableMap>(&item_value);
        if (item_map == nullptr) {
          continue;
        }
        data.items.push_back({
            GetString(*item_map, "particulars"),
            GetString(*item_map, "hsnCode"),
            GetString(*item_map, "quantityPcs"),
            GetString(*item_map, "weight"),
        });
      }
    }
  }

  return data;
}

int MmToPixelsX(HDC hdc, int millimeters) {
  return ::MulDiv(millimeters * 100, ::GetDeviceCaps(hdc, LOGPIXELSX), 2540);
}

int MmToPixelsY(HDC hdc, int millimeters) {
  return ::MulDiv(millimeters * 100, ::GetDeviceCaps(hdc, LOGPIXELSY), 2540);
}

HFONT CreateFontForPoints(HDC hdc, int point_size, int weight) {
  LOGFONTW font = {};
  font.lfHeight = -::MulDiv(point_size, ::GetDeviceCaps(hdc, LOGPIXELSY), 72);
  font.lfWeight = weight;
  wcscpy_s(font.lfFaceName, L"Arial");
  return ::CreateFontIndirectW(&font);
}

void DrawTextInRect(HDC hdc, HFONT font, const std::wstring& text, RECT rect,
                    UINT format) {
  const auto old_font = ::SelectObject(hdc, font);
  ::SetBkMode(hdc, TRANSPARENT);
  ::DrawTextW(hdc, text.c_str(), static_cast<int>(text.size()), &rect, format);
  ::SelectObject(hdc, old_font);
}

void DrawCellText(HDC hdc, HFONT font, const std::wstring& text, RECT rect,
                  UINT format = DT_LEFT | DT_VCENTER | DT_SINGLELINE) {
  const int padding_x = MmToPixelsX(hdc, 2);
  const int padding_y = MmToPixelsY(hdc, 1);
  ::InflateRect(&rect, -padding_x, -padding_y);
  DrawTextInRect(hdc, font, text, rect, format | DT_END_ELLIPSIS);
}

std::wstring JoinLine(const std::wstring& label, const std::wstring& value) {
  return label + L": " + value;
}

void DrawChallanDocument(HDC hdc, const ChallanPrintData& data) {
  const int page_width = ::GetDeviceCaps(hdc, HORZRES);
  const int page_height = ::GetDeviceCaps(hdc, VERTRES);
  const int margin_x = MmToPixelsX(hdc, 10);
  const int margin_y = MmToPixelsY(hdc, 10);
  const int max_doc_width = MmToPixelsX(hdc, 186);
  int doc_width = std::min(page_width - (margin_x * 2), max_doc_width);
  int doc_left = std::max(margin_x, (page_width - doc_width) / 2);
  int cursor_y = margin_y;

  const int top_height = MmToPixelsY(hdc, 32);
  const int info_height = MmToPixelsY(hdc, 28);
  const int table_header_height = MmToPixelsY(hdc, 10);
  const int bottom_height = MmToPixelsY(hdc, 40);
  const int row_count = std::max(9, static_cast<int>(data.items.size()));
  const int available_table_height =
      page_height - (margin_y * 2) - top_height - info_height -
      table_header_height - bottom_height;
  const int row_height =
      std::max(MmToPixelsY(hdc, 6), available_table_height / row_count);
  const int table_height = table_header_height + (row_height * row_count);
  const int doc_height = top_height + info_height + table_height + bottom_height;
  const int doc_right = doc_left + doc_width;

  HFONT title_font = CreateFontForPoints(hdc, 12, FW_BOLD);
  HFONT company_font = CreateFontForPoints(hdc, 20, FW_BOLD);
  HFONT regular_font = CreateFontForPoints(hdc, 10, FW_NORMAL);
  HFONT bold_font = CreateFontForPoints(hdc, 10, FW_BOLD);

  RECT doc_rect = {doc_left, cursor_y, doc_right, cursor_y + doc_height};
  ::Rectangle(hdc, doc_rect.left, doc_rect.top, doc_rect.right, doc_rect.bottom);

  RECT top_rect = {doc_left, cursor_y, doc_right, cursor_y + top_height};
  RECT title_rect = {doc_left, cursor_y + MmToPixelsY(hdc, 3), doc_right,
                     cursor_y + MmToPixelsY(hdc, 10)};
  DrawTextInRect(hdc, title_font, data.doc_title, title_rect,
                 DT_CENTER | DT_VCENTER | DT_SINGLELINE);

  RECT mobile_rect = {doc_left, cursor_y + MmToPixelsY(hdc, 3),
                      doc_right - MmToPixelsX(hdc, 3),
                      cursor_y + MmToPixelsY(hdc, 10)};
  if (!data.mobile.empty()) {
    DrawTextInRect(hdc, bold_font, L"Mobile: " + data.mobile, mobile_rect,
                   DT_RIGHT | DT_VCENTER | DT_SINGLELINE);
  }

  RECT company_rect = {doc_left, cursor_y + MmToPixelsY(hdc, 11), doc_right,
                       cursor_y + MmToPixelsY(hdc, 20)};
  DrawTextInRect(hdc, company_font, data.company_name, company_rect,
                 DT_CENTER | DT_VCENTER | DT_SINGLELINE);

  RECT description_rect = {doc_left + MmToPixelsX(hdc, 8),
                           cursor_y + MmToPixelsY(hdc, 20),
                           doc_right - MmToPixelsX(hdc, 8),
                           cursor_y + MmToPixelsY(hdc, 25)};
  DrawTextInRect(hdc, regular_font, data.business_description, description_rect,
                 DT_CENTER | DT_VCENTER | DT_SINGLELINE);

  RECT address_rect = {doc_left + MmToPixelsX(hdc, 8),
                       cursor_y + MmToPixelsY(hdc, 25),
                       doc_right - MmToPixelsX(hdc, 8), top_rect.bottom};
  DrawTextInRect(hdc, regular_font, data.address, address_rect,
                 DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  cursor_y += top_height;
  ::MoveToEx(hdc, doc_left, cursor_y, nullptr);
  ::LineTo(hdc, doc_right, cursor_y);

  const int right_info_width = MmToPixelsX(hdc, 62);
  const int split_x = doc_right - right_info_width;
  RECT left_info = {doc_left, cursor_y, split_x, cursor_y + info_height};
  RECT right_info = {split_x, cursor_y, doc_right, cursor_y + info_height};
  ::MoveToEx(hdc, split_x, cursor_y, nullptr);
  ::LineTo(hdc, split_x, cursor_y + info_height);

  const std::wstring party_text =
      JoinLine(data.party_label, data.party_name) + L"\n" +
      JoinLine(L"GSTIN", data.party_gstin) + L"\n" +
      JoinLine(L"Location", data.location);
  DrawCellText(hdc, regular_font, party_text, left_info,
               DT_LEFT | DT_TOP | DT_WORDBREAK);

  const std::wstring reference_text =
      JoinLine(data.reference_label, data.reference_value) + L"\n" +
      JoinLine(L"Challan No.", data.challan_no) + L"\n" +
      JoinLine(L"Date", data.date);
  DrawCellText(hdc, regular_font, reference_text, right_info,
               DT_LEFT | DT_TOP | DT_WORDBREAK);
  cursor_y += info_height;
  ::MoveToEx(hdc, doc_left, cursor_y, nullptr);
  ::LineTo(hdc, doc_right, cursor_y);

  const int col_particulars = doc_left + (doc_width * 52 / 100);
  const int col_hsn = doc_left + (doc_width * 68 / 100);
  const int col_qty = doc_left + (doc_width * 84 / 100);
  const int cols[] = {doc_left, col_particulars, col_hsn, col_qty, doc_right};

  for (int col : cols) {
    ::MoveToEx(hdc, col, cursor_y, nullptr);
    ::LineTo(hdc, col, cursor_y + table_height);
  }

  RECT header_cells[] = {
      {cols[0], cursor_y, cols[1], cursor_y + table_header_height},
      {cols[1], cursor_y, cols[2], cursor_y + table_header_height},
      {cols[2], cursor_y, cols[3], cursor_y + table_header_height},
      {cols[3], cursor_y, cols[4], cursor_y + table_header_height},
  };
  DrawCellText(hdc, bold_font, L"Particulars", header_cells[0]);
  DrawCellText(hdc, bold_font, L"HSN Code", header_cells[1]);
  DrawCellText(hdc, bold_font, L"QTY. Pcs.", header_cells[2]);
  DrawCellText(hdc, bold_font, L"Weight", header_cells[3]);

  cursor_y += table_header_height;
  ::MoveToEx(hdc, doc_left, cursor_y, nullptr);
  ::LineTo(hdc, doc_right, cursor_y);

  for (int row = 0; row < row_count; ++row) {
    const int row_bottom = cursor_y + row_height;
    const ChallanPrintItem* item =
        row < static_cast<int>(data.items.size()) ? &data.items[row] : nullptr;
    RECT cells[] = {
        {cols[0], cursor_y, cols[1], row_bottom},
        {cols[1], cursor_y, cols[2], row_bottom},
        {cols[2], cursor_y, cols[3], row_bottom},
        {cols[3], cursor_y, cols[4], row_bottom},
    };
    if (item != nullptr) {
      DrawCellText(hdc, regular_font, item->particulars, cells[0]);
      DrawCellText(hdc, regular_font, item->hsn_code, cells[1]);
      DrawCellText(hdc, regular_font, item->quantity_pcs, cells[2]);
      DrawCellText(hdc, regular_font, item->weight, cells[3]);
    }
    cursor_y = row_bottom;
    ::MoveToEx(hdc, doc_left, cursor_y, nullptr);
    ::LineTo(hdc, doc_right, cursor_y);
  }

  const int bottom_split_x = doc_right - MmToPixelsX(hdc, 68);
  RECT bottom_left = {doc_left, cursor_y, bottom_split_x,
                      cursor_y + bottom_height};
  RECT bottom_right = {bottom_split_x, cursor_y, doc_right,
                       cursor_y + bottom_height};
  ::MoveToEx(hdc, bottom_split_x, cursor_y, nullptr);
  ::LineTo(hdc, bottom_split_x, cursor_y + bottom_height);

  const std::wstring receiver_text =
      JoinLine(L"State Code", data.state_code) + L"\n" +
      JoinLine(L"GSTIN", data.gstin) + L"\n\n\nReceiver's Signature";
  DrawCellText(hdc, regular_font, receiver_text, bottom_left,
               DT_LEFT | DT_TOP | DT_WORDBREAK);

  const std::wstring signatory_text =
      L"For " + data.company_name + L"\n\n\n" + data.signature_label;
  DrawCellText(hdc, regular_font, signatory_text, bottom_right,
               DT_RIGHT | DT_TOP | DT_WORDBREAK);

  ::DeleteObject(title_font);
  ::DeleteObject(company_font);
  ::DeleteObject(regular_font);
  ::DeleteObject(bold_font);
}

bool PrintChallanDocument(HDC hdc, const ChallanPrintData& data, int copies) {
  DOCINFOW doc_info = {};
  doc_info.cbSize = sizeof(doc_info);
  const std::wstring doc_name =
      data.challan_no.empty() ? L"Challan" : L"Challan " + data.challan_no;
  doc_info.lpszDocName = doc_name.c_str();

  if (::StartDocW(hdc, &doc_info) <= 0) {
    return false;
  }

  const int safe_copies = std::max(1, copies);
  for (int copy = 0; copy < safe_copies; ++copy) {
    if (::StartPage(hdc) <= 0) {
      ::AbortDoc(hdc);
      return false;
    }
    DrawChallanDocument(hdc, data);
    if (::EndPage(hdc) <= 0) {
      ::AbortDoc(hdc);
      return false;
    }
  }

  return ::EndDoc(hdc) > 0;
}

void FreePrintDialogHandles(const PRINTDLGW& dialog) {
  if (dialog.hDC != nullptr) {
    ::DeleteDC(dialog.hDC);
  }
  if (dialog.hDevMode != nullptr) {
    ::GlobalFree(dialog.hDevMode);
  }
  if (dialog.hDevNames != nullptr) {
    ::GlobalFree(dialog.hDevNames);
  }
}

std::wstring QuoteShellArgument(const std::wstring& value) {
  std::wstring quoted = L"\"";
  int trailing_backslashes = 0;
  for (const wchar_t ch : value) {
    if (ch == L'\\') {
      ++trailing_backslashes;
      quoted.push_back(ch);
      continue;
    }
    if (ch == L'"') {
      quoted.append(trailing_backslashes + 1, L'\\');
    }
    trailing_backslashes = 0;
    quoted.push_back(ch);
  }
  quoted.append(trailing_backslashes, L'\\');
  quoted.push_back(L'"');
  return quoted;
}

bool SelectedPrinterFromDialog(const PRINTDLGW& dialog,
                               SelectedPrinter* printer) {
  if (dialog.hDevNames == nullptr || printer == nullptr) {
    return false;
  }

  const auto dev_names =
      static_cast<DEVNAMES*>(::GlobalLock(dialog.hDevNames));
  if (dev_names == nullptr) {
    return false;
  }

  const auto base = reinterpret_cast<const wchar_t*>(dev_names);
  printer->driver = base + dev_names->wDriverOffset;
  printer->name = base + dev_names->wDeviceOffset;
  printer->port = base + dev_names->wOutputOffset;
  ::GlobalUnlock(dialog.hDevNames);
  return !printer->name.empty();
}

bool PrintPdfFileWithSystemHandler(HWND owner, const std::wstring& file_path,
                                   DWORD* error_code) {
  if (file_path.empty() || ::GetFileAttributesW(file_path.c_str()) ==
                               INVALID_FILE_ATTRIBUTES) {
    *error_code = ERROR_FILE_NOT_FOUND;
    return false;
  }

  PRINTDLGW dialog = {};
  dialog.lStructSize = sizeof(dialog);
  dialog.hwndOwner = owner;
  dialog.Flags = PD_ALLPAGES | PD_HIDEPRINTTOFILE | PD_NOSELECTION |
                 PD_NOPAGENUMS | PD_RETURNDC |
                 PD_USEDEVMODECOPIESANDCOLLATE;
  dialog.nMinPage = 1;
  dialog.nMaxPage = 1;
  dialog.nFromPage = 1;
  dialog.nToPage = 1;
  dialog.nCopies = 1;

  const BOOL accepted = ::PrintDlgW(&dialog);
  if (!accepted) {
    FreePrintDialogHandles(dialog);
    *error_code = ::CommDlgExtendedError();
    return false;
  }

  SelectedPrinter printer;
  const bool has_printer = SelectedPrinterFromDialog(dialog, &printer);
  FreePrintDialogHandles(dialog);
  if (!has_printer) {
    *error_code = ERROR_INVALID_PRINTER_NAME;
    return false;
  }

  const std::wstring parameters =
      QuoteShellArgument(printer.name) + L" " +
      QuoteShellArgument(printer.driver) + L" " +
      QuoteShellArgument(printer.port);

  SHELLEXECUTEINFOW execute_info = {};
  execute_info.cbSize = sizeof(execute_info);
  execute_info.fMask = SEE_MASK_NOCLOSEPROCESS;
  execute_info.hwnd = owner;
  execute_info.lpVerb = L"printto";
  execute_info.lpFile = file_path.c_str();
  execute_info.lpParameters = parameters.c_str();
  execute_info.nShow = SW_HIDE;

  if (!::ShellExecuteExW(&execute_info)) {
    const DWORD shell_error = ::GetLastError();
    const HINSTANCE chooser_result = ::ShellExecuteW(
        owner, nullptr, L"rundll32.exe",
        (L"shell32.dll,OpenAs_RunDLL " + QuoteShellArgument(file_path)).c_str(),
        nullptr, SW_SHOWNORMAL);
    if (reinterpret_cast<INT_PTR>(chooser_result) > 32) {
      *error_code = 0;
      return true;
    }
    *error_code = shell_error;
    return false;
  }

  if (execute_info.hProcess != nullptr) {
    ::CloseHandle(execute_info.hProcess);
  }
  *error_code = 0;
  return true;
}

bool ShowWindowsPrintDialog(HWND owner, const ChallanPrintData& data,
                            DWORD* error_code) {
  PRINTDLGW dialog = {};
  dialog.lStructSize = sizeof(dialog);
  dialog.hwndOwner = owner;
  dialog.Flags = PD_ALLPAGES | PD_HIDEPRINTTOFILE | PD_NOSELECTION |
                 PD_NOPAGENUMS | PD_RETURNDC |
                 PD_USEDEVMODECOPIESANDCOLLATE;
  dialog.nMinPage = 1;
  dialog.nMaxPage = 1;
  dialog.nFromPage = 1;
  dialog.nToPage = 1;
  dialog.nCopies = 1;

  const BOOL accepted = ::PrintDlgW(&dialog);

  if (accepted) {
    const bool printed =
        PrintChallanDocument(dialog.hDC, data, dialog.nCopies);
    FreePrintDialogHandles(dialog);
    *error_code = printed ? 0 : ::GetLastError();
    return printed;
  }

  FreePrintDialogHandles(dialog);
  *error_code = ::CommDlgExtendedError();
  return false;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  native_printing_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "paper/native_printing",
          &flutter::StandardMethodCodec::GetInstance());
  native_printing_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "showPrintDialog") {
          const auto data = PrintDataFromArguments(call.arguments());
          DWORD error_code = 0;
          const bool accepted =
              ShowWindowsPrintDialog(GetHandle(), data, &error_code);
          if (accepted) {
            result->Success(flutter::EncodableValue(true));
            return;
          }
          if (error_code == 0) {
            result->Success(flutter::EncodableValue(false));
            return;
          }
          result->Error("PRINT_DIALOG_FAILED",
                        "Windows could not open the print dialog.",
                        flutter::EncodableValue(static_cast<int>(error_code)));
          return;
        }

        if (call.method_name() == "printPdfFile") {
          DWORD error_code = 0;
          const bool printed = PrintPdfFileWithSystemHandler(
              GetHandle(), GetArgumentString(call.arguments(), "filePath"),
              &error_code);
          if (printed) {
            result->Success(flutter::EncodableValue(true));
            return;
          }
          if (error_code == 0) {
            result->Success(flutter::EncodableValue(false));
            return;
          }
          result->Error("PDF_PRINT_FAILED",
                        "Windows could not send the PDF to the selected printer.",
                        flutter::EncodableValue(static_cast<int>(error_code)));
          return;
        }

        result->NotImplemented();
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  native_printing_channel_.reset();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
