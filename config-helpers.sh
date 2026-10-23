#!/bin/bash

# Resolves a yes/no setting and returns 0 for yes, 1 for no.
#
# Usage: resolveYesNoSetting <settingName> <question> [defaultAnswer=y]
#
# - <settingName> is the NAME of the variable (e.g. setupSsh), not its value. It is
#   read and written by name, so a value set in setup.conf is used without prompting.
# - If the variable is empty the user is asked <question>; Enter selects <defaultAnswer>.
# - Accepts y/yes/n/no (any case). The normalized answer is stored back in the variable.
# - The variable is exported so child scripts reuse the answer instead of asking again.
resolveYesNoSetting() {

    local settingName="$1"
    local question="$2"
    local defaultAnswer="${3:-y}"
    local choiceHint="[Y/n]"

    [[ "${defaultAnswer}" =~ ^[Nn]([Oo])?$ ]] && choiceHint="[y/N]"

    # Prompt only if not already set (config file or environment)
    [[ -n "${!settingName}" ]] || read -r -p "${question} ${choiceHint}: " "${settingName}"

    printf -v "${settingName}" '%s' "${!settingName:-${defaultAnswer}}"
    export "${settingName}"

    [[ "${!settingName}" =~ ^[Yy]([Ee][Ss])?$ ]]

}
