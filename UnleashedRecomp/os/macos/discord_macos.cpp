#include <os/discord.h>
#include <os/logger.h>
#include <user/config.h>

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

enum : int32_t { OP_HANDSHAKE = 0, OP_FRAME = 1 };

static bool SendFrame(int fd, int32_t op, const std::string& json)
{
    int32_t header[2] = { op, (int32_t)json.size() }; // Discord IPC is little endian, as is arm64/x86_64.
    std::string buf((const char*)header, sizeof(header));
    buf += json;
    return send(fd, buf.data(), buf.size(), 0) == (ssize_t)buf.size();
}

static int Connect()
{
    const char* tmp = getenv("TMPDIR");
    std::string dir = tmp ? tmp : "/tmp/";
    if (dir.back() != '/')
        dir += '/';

    for (int i = 0; i < 10; i++)
    {
        sockaddr_un addr{};
        addr.sun_family = AF_UNIX;
        snprintf(addr.sun_path, sizeof(addr.sun_path), "%sdiscord-ipc-%d", dir.c_str(), i);

        int fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (fd < 0)
            return -1;

        if (connect(fd, (sockaddr*)&addr, sizeof(addr)) == 0)
            return fd;

        close(fd);
    }

    return -1;
}

static void DiscordThread(std::string appId)
{
    using namespace std::chrono_literals;

    auto start = std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::now().time_since_epoch()).count();

    while (true)
    {
        int fd = Connect();
        if (fd >= 0)
        {
            int one = 1;
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));

            auto activity = fmt::format(
                R"({{"cmd":"SET_ACTIVITY","nonce":"1","args":{{"pid":{},"activity":{{"timestamps":{{"start":{}}},)"
                R"("assets":{{"large_image":"unleashed_icon","large_text":"Sonic Unleashed on macOS"}},)"
                R"("buttons":[{{"label":"Original PC port by hedge-dev","url":"https://github.com/hedge-dev/UnleashedRecomp"}},)"
                R"({{"label":"Get the macOS port","url":"https://github.com/koels/UnleashedRecomp-macOS"}}]}}}}}})",
                getpid(), start);

            char buf[4096];

            // Discord ignores commands sent before it replies to the handshake with READY.
            if (SendFrame(fd, OP_HANDSHAKE, fmt::format(R"({{"v":1,"client_id":"{}"}})", appId)) &&
                recv(fd, buf, sizeof(buf), 0) > 0 &&
                SendFrame(fd, OP_FRAME, activity))
            {
                LOGN("Discord Rich Presence connected.");

                // Drain replies until Discord closes the socket.
                while (recv(fd, buf, sizeof(buf), 0) > 0);
            }

            close(fd);
        }

        // Discord isn't running or went away; retry later.
        std::this_thread::sleep_for(15s);
    }
}

void os::discord::Init()
{
    const std::string& appId = Config::DiscordApplicationId.Value;
    if (appId.empty() || appId.find_first_not_of("0123456789") != std::string::npos)
        return;

    std::thread(DiscordThread, appId).detach();
}
