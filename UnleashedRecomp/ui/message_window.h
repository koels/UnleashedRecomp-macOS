#pragma once

#define MSG_OPEN   (false)
#define MSG_CLOSED (true)

class MessageWindow
{
public:
    static inline bool s_isVisible = false;

    static void Init();
    static void Draw();
    static bool Open(std::string text, int* result, std::span<std::string> buttons = {}, int defaultButtonIndex = 0, int cancelButtonIndex = 1);
    static void Close();

    // Progress mode: no buttons, no "Next" prompt, and the text can change while it is open.
    static void OpenProgress(std::string text);
    static void SetText(std::string text);
};
