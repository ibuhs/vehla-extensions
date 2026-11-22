import Foundation

/// How to launch the user's shell, with light hooks that tell the Notch where you are and when a command
/// starts and ends. The user's own startup files still run first, untouched.
public struct ShellLaunch: Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]
    /// True when the shell reports command start/finish (zsh); bash reports prompts and exit codes only.
    public var reportsCommands: Bool
    public var name: String

    public init(executable: String, arguments: [String], environment: [String: String], reportsCommands: Bool, name: String) {
        self.executable = executable; self.arguments = arguments; self.environment = environment
        self.reportsCommands = reportsCommands; self.name = name
    }
}

public enum ShellIntegration {
    public static func prepare(directory: URL, shell: String? = nil, baseEnvironment: [String: String],
                               home: String) throws -> ShellLaunch {
        let executable = shell ?? baseEnvironment["SHELL"] ?? "/bin/zsh"
        let name = (executable as NSString).lastPathComponent
        var env = baseEnvironment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "VehlaNotch"
        env["TERM_PROGRAM_VERSION"] = "1"
        env["SHELL_SESSIONS_DISABLE"] = "1"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        ["TERM_SESSION_ID", "ITERM_SESSION_ID", "INSIDE_EMACS"].forEach { env[$0] = nil }

        // While this file exists the prompt is just "%" (or "$"); remove it and your own prompt returns.
        env["VEHLA_PROMPT_FLAG"] = directory.appendingPathComponent("minimal-prompt").path

        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        switch name {
        case "zsh":
            let zdir = directory.appendingPathComponent("zsh", isDirectory: true)
            try fm.createDirectory(at: zdir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            env["VEHLA_USER_ZDOTDIR"] = baseEnvironment["ZDOTDIR"] ?? home
            env["ZDOTDIR"] = zdir.path
            try write(zshenv, to: zdir.appendingPathComponent(".zshenv"))
            try write(zprofile, to: zdir.appendingPathComponent(".zprofile"))
            try write(zshrc, to: zdir.appendingPathComponent(".zshrc"))
            return ShellLaunch(executable: executable, arguments: ["-l", "-i"], environment: env, reportsCommands: true, name: name)
        case "bash":
            let bdir = directory.appendingPathComponent("bash", isDirectory: true)
            try fm.createDirectory(at: bdir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let rc = bdir.appendingPathComponent("bashrc")
            try write(bashrc, to: rc)
            return ShellLaunch(executable: executable, arguments: ["--rcfile", rc.path, "-i"], environment: env, reportsCommands: false, name: name)
        default:
            return ShellLaunch(executable: executable, arguments: [], environment: env, reportsCommands: false, name: name)
        }
    }

    private static func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static let zshenv = #"""
    # Vehla mini terminal: run your own startup files, then add prompt marks.
    export HISTFILE="${HISTFILE:-${VEHLA_USER_ZDOTDIR:-$HOME}/.zsh_history}"
    [[ -f "${VEHLA_USER_ZDOTDIR:-$HOME}/.zshenv" ]] && source "${VEHLA_USER_ZDOTDIR:-$HOME}/.zshenv"
    """# + "\n"

    static let zprofile = #"""
    [[ -f "${VEHLA_USER_ZDOTDIR:-$HOME}/.zprofile" ]] && source "${VEHLA_USER_ZDOTDIR:-$HOME}/.zprofile"
    """# + "\n"

    static let zshrc = #"""
    # Hand control back to your own config first; zsh then reads your other files from your own directory.
    ZDOTDIR="${VEHLA_USER_ZDOTDIR:-$HOME}"
    [[ -f "$ZDOTDIR/.zshrc" ]] && source "$ZDOTDIR/.zshrc"
    # Marks the Vehla Notch reads: command text, start, finish with exit status, and the working directory.
    __vn_precmd() { local __vn_ec=$?; printf '\e]133;D;%s\a\e]7;file://%s%s\a\e]133;A\a' "$__vn_ec" "${HOST}" "${PWD}"; }
    __vn_preexec() { local __vn_cmd="${1//[$'\e\a']/}"; printf '\e]7777;%s\a\e]133;C\a' "${__vn_cmd//$'\n'/ }"; }
    precmd_functions=(__vn_precmd ${precmd_functions[@]:#__vn_precmd})
    preexec_functions=(${preexec_functions[@]:#__vn_preexec} __vn_preexec)
    # Minimal prompt: just "%" and the cursor, switchable live. It runs last so it wins over prompt themes, and
    # your own prompt is put back the moment the flag file is removed.
    __vn_style() {
      if [[ -n "$VEHLA_PROMPT_FLAG" && -f "$VEHLA_PROMPT_FLAG" ]]; then
        if [[ -z "$__vn_minimal" ]]; then __vn_saved_prompt="$PROMPT"; __vn_saved_rprompt="$RPROMPT"; __vn_minimal=1; fi
        PROMPT='%# '; RPROMPT=''
      elif [[ -n "$__vn_minimal" ]]; then
        PROMPT="$__vn_saved_prompt"; RPROMPT="$__vn_saved_rprompt"; unset __vn_minimal
      fi
    }
    precmd_functions=(${precmd_functions[@]:#__vn_style} __vn_style)
    """# + "\n"

    static let bashrc = #"""
    [ -f /etc/profile ] && . /etc/profile
    for f in ~/.bash_profile ~/.bash_login ~/.profile; do [ -f "$f" ] && { . "$f"; break; }; done
    [ -f ~/.bashrc ] && . ~/.bashrc
    __vn_prompt() { local ec=$?; printf '\e]133;D;%s\a\e]7;file://%s%s\a\e]133;A\a' "$ec" "$HOSTNAME" "$PWD"; }
    PROMPT_COMMAND="__vn_prompt${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
    __vn_style() {
      if [ -n "$VEHLA_PROMPT_FLAG" ] && [ -f "$VEHLA_PROMPT_FLAG" ]; then
        if [ -z "$__vn_minimal" ]; then __vn_saved_ps1="$PS1"; __vn_minimal=1; fi
        PS1='\$ '
      elif [ -n "$__vn_minimal" ]; then
        PS1="$__vn_saved_ps1"; unset __vn_minimal
      fi
    }
    PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}__vn_style"
    """# + "\n"
}
