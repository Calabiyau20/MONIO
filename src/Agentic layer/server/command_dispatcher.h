#pragma once

#include "../common/bridge_controllers.h"
#include "../common/ipc_protocol.h"
#include "../common/parsed_args.h"
#include <functional>
#include <map>
#include <mutex>
#include <string>
#include <string_view>

namespace agentic {

class CommandDispatcher {
public:
    CommandDispatcher();
    explicit CommandDispatcher(BridgeControllers controllers);

    void setControllers(BridgeControllers controllers);
    [[nodiscard]] BridgeControllers getControllers() const;

    // Execute parsed raw line string and return formatted text payload
    std::string executeCommand(std::string_view commandLine);

    // Direct execution returning structured ExecutionResult
    ExecutionResult dispatch(const ParsedArgs& args);

private:
    void registerHandlers();

    BridgeControllers m_controllers{};
    bool m_controllersReady{false};
    // Guards m_controllers/m_controllersReady: setControllers() runs on the
    // GUI thread after async boot while dispatch() runs on the IPC thread.
    mutable std::mutex m_controllersMutex{};
    using HandlerFunc = std::function<ExecutionResult(const ParsedArgs&)>;
    std::map<std::string, HandlerFunc> m_verbHandlers{};
};

} // namespace agentic
