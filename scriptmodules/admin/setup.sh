#!/usr/bin/env bash

# This file is part of The RetroPie Project
# 
# The RetroPie Project is the legal property of its developers, whose names are
# too numerous to list here. Please refer to the COPYRIGHT.md file distributed with this source.
# 
# See the LICENSE.md file at the top-level directory of this distribution and 
# at https://raw.githubusercontent.com/RetroPie/RetroPie-Setup/master/LICENSE.md
#

rp_module_id="setup"
rp_module_desc="GUI based setup for RetroPie"
rp_module_section=""

function rps_logInit() {
    if [[ ! -d "$__logdir" ]]; then
        if mkdir -p "$__logdir"; then
            chown $user:$user "$__logdir"
        else
            fatalError "Couldn't make directory $__logdir"
        fi
    fi
    local now=$(date +'%Y-%m-%d_%H%M%S')
    logfilename="$__logdir/rps_$now.log.gz"
    touch "$logfilename"
    chown $user:$user "$logfilename"
    time_start=$(date +"%s")
}

function rps_logStart() {
    echo "Log started at: $(date -d @$time_start)"
}

function rps_logEnd() {
    time_end=$(date +"%s")
    echo
    echo "Log ended at: $(date -d @$time_end)"
    date_total=$((time_end-time_start))
    local hours=$((date_total / 60 / 60 % 24))
    local mins=$((date_total / 60 % 60))
    local secs=$((date_total % 60))
    echo "Total running time: $hours hours, $mins mins, $secs secs"
}

function rps_printInfo() {
    reset
    if [[ ${#__ERRMSGS[@]} -gt 0 ]]; then
        printMsgs "dialog" "${__ERRMSGS[@]}"
        printMsgs "dialog" "Please see $1 for more in depth information regarding the errors."
    fi
    if [[ ${#__INFMSGS[@]} -gt 0 ]]; then
        printMsgs "dialog" "${__INFMSGS[@]}"
    fi
}

function depends_setup() {
    if [[ "$__raspbian_ver" -eq 7 ]]; then
        printMsgs "dialog" "Raspbian Wheezy is no longer supported. Binaries are no longer updated and new emulators may fail to build, install or run.\n\nPlease backup your system and start from the latest image."
    fi
    # check for VERSION file - if it doesn't exist we will run the post_update script as it won't be triggered
    # on first upgrade to 4.x
    if [[ ! -f "$rootdir/VERSION" ]]; then
        exec "$scriptdir/retropie_packages.sh" setup post_update gui_setup
    fi
    if isPlatform "rpi" && [[ -f /boot/config.txt ]] && grep -q "^dtoverlay=vc4-kms-v3d" /boot/config.txt; then
        printMsgs "dialog" "You have the experimental desktop GL driver enabled. This is NOT compatible with RetroPie, and Emulation Station as well as emulators will fail to launch. Please disable the experimental desktop GL driver from the raspi-config 'Advanced Options' menu."
    fi
}

function updatescript_setup()
{
    chown -R $user:$user "$scriptdir"
    printHeading "Fetching latest version of the RetroPie Setup Script."
    pushd "$scriptdir" >/dev/null
    if [[ ! -d ".git" ]]; then
        printMsgs "dialog" "Cannot find directory '.git'. Please clone the RetroPie Setup script via 'git clone https://github.com/RetroPie/RetroPie-Setup.git'"
        popd >/dev/null
        return 1
    fi
    local error
    if ! error=$(su $user -c "git pull 2>&1 >/dev/null"); then
        printMsgs "dialog" "Update failed:\n\n$error"
        popd >/dev/null
        return 1
    fi
    popd >/dev/null

    printMsgs "dialog" "Fetched the latest version of the RetroPie Setup script."
    return 0
}

function post_update_setup() {
    local return_func=("$@")

    echo "$__version" >"$rootdir/VERSION"

    # run _update_hook_id functions - eg to fix up modules for retropie-setup 4.x install detection
    rp_updateHooks

    printMsgs "dialog" "NOTICE: The RetroPie-Setup script and pre-made RetroPie SD card images are available to download for free from https://retropie.org.uk.\n\nIt has come to our attention that some people are profiting from selling RetroPie SD cards, some including copyrighted games. This is illegal.\n\nIf you have been sold this software on its own or including games, you can let us know about it by emailing retropieproject@gmail.com"

    # return to set return function
    "${return_func[@]}"
}

function package_setup() {
    local idx="$1"
    local md_id="${__mod_id[$idx]}"

    while true; do
        local options=()

        local install
        local status
        if rp_isInstalled "$idx"; then
            install="Update"
            status="Installed"
        else
            install="Install"
            status="Not installed"
        fi

        if rp_hasBinary "$idx"; then
            options+=(B "$install from binary")
        fi

        if fnExists "sources_${md_id}"; then
            options+=(S "$install from source")
        fi

        if rp_isInstalled "$idx"; then
            if fnExists "gui_${md_id}"; then
                options+=(C "Configuration / Options")
            fi
            options+=(X "Remove")
        fi

        local help="${__mod_desc[$idx]}\n\n${__mod_help[$idx]}"
        if [[ -n "$help" ]]; then
            options+=(H "Package Help")
        fi

        cmd=(dialog --backtitle "$__backtitle" --cancel-label "Back" --menu "Choose an option for ${__mod_id[$idx]} ($status)" 22 76 16)
        choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)

        local logfilename
        __ERRMSGS=()
        __INFMSGS=()

        case "$choice" in
            B|I)
                rps_logInit
                {
                    rps_logStart
                    rp_installModule "$idx"
                    rps_logEnd
                } &> >(tee >(gzip --stdout >"$logfilename"))
                rps_printInfo "$logfilename"
                ;;
            S)
                rps_logInit
                {
                    rps_logStart
                    rp_callModule "$idx"
                    rps_logEnd
                } &> >(tee >(gzip --stdout >"$logfilename"))
                rps_printInfo "$logfilename"
                ;;
            C)
                rps_logInit
                {
                    rps_logStart
                    rp_callModule "$idx" gui
                    rps_logEnd
                } &> >(tee >(gzip --stdout >"$logfilename"))
                rps_printInfo "$logfilename"
                ;;
            X)
                local text="Are you sure you want to remove $md_id?"
                [[ "${__mod_section[$idx]}" == "core" ]] && text+="\n\nWARNING - core packages are needed for RetroPie to function!"
                dialog --defaultno --yesno "$text" 22 76 2>&1 >/dev/tty || continue
                rps_logInit
                {
                    rps_logStart
                    rp_callModule "$idx" remove
                    rps_logEnd
                } &> >(tee >(gzip --stdout >"$logfilename"))
                rps_printInfo "$logfilename"
                ;;
            H)
                printMsgs "dialog" "$help"
                ;;
            *)
                break
                ;;
        esac

    done
}

function section_gui_setup() {
    local section="$1"

    local default=""
    while true; do
        local options=()

        # we don't build binaries for experimental packages
        if rp_hasBinaries && [[ "$section" != "exp" ]]; then
            options+=(B "Install/Update all ${__sections[$section]} packages from binary" "This will install all ${__sections[$section]} packages from binary archives (if available). If a binary archive is missing a source install will be performed.")
        fi

        options+=(
            S "Install/Update all ${__sections[$section]} packages from source" "S This will build and install all the packages from $section from source. Building from source will pull in the very latest releases of many of the emulators. Building could fail or resulting binaries could not work. Only choose this option if you are comfortable in working with the linux console and debugging any issues."
            X "Remove all ${__sections[$section]} packages" "X This will remove all $section packages."
        )

        local idx
        for idx in $(rp_getSectionIds $section); do
            if rp_isInstalled "$idx"; then
                installed="(Installed)"
            else
                installed=""
            fi
            options+=("$idx" "${__mod_id[$idx]} $installed" "$idx ${__mod_desc[$idx]}"$'\n\n'"${__mod_help[$idx]}")
        done

        local cmd=(dialog --backtitle "$__backtitle" --cancel-label "Back" --item-help --help-button --default-item "$default" --menu "Choose an option" 22 76 16)

        local choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
        [[ -z "$choice" ]] && break
        if [[ "${choice[@]:0:4}" == "HELP" ]]; then
            # remove HELP
            choice="${choice[@]:5}"
            # get id of menu item
            default="${choice/%\ */}"
            # remove id
            choice="${choice#* }"
            printMsgs "dialog" "$choice"
            continue
        fi

        default="$choice"

        local logfilename
        __ERRMSGS=()
        __INFMSGS=()
        case "$choice" in
            B)
                dialog --defaultno --yesno "Are you sure you want to install/update all $section packages from binary?" 22 76 2>&1 >/dev/tty || continue
                rps_logInit
                {
                    rps_logStart
                    for idx in $(rp_getSectionIds $section); do
                        rp_installModule "$idx"
                    done
                    rps_logEnd
                } &> >(tee >(gzip --stdout >"$logfilename"))
                rps_printInfo "$logfilename"
                ;;
            S)
                dialog --defaultno --yesno "Are you sure you want to install/update all $section packages from source?" 22 76 2>&1 >/dev/tty || continue
                rps_logInit
                {
                    rps_logStart
                    for idx in $(rp_getSectionIds $section); do
                        rp_callModule "$idx"
                    done
                    rps_logEnd
                } &> >(tee >(gzip --stdout >"$logfilename"))
                rps_printInfo "$logfilename"
                ;;

            X)
                local text="Are you sure you want to remove all $section packages?"
                [[ "$section" == "core" ]] && text+="\n\nWARNING - core packages are needed for RetroPie to function!"
                dialog --defaultno --yesno "$text" 22 76 2>&1 >/dev/tty || continue
                rps_logInit
                {
                    rps_logStart
                    for idx in $(rp_getSectionIds $section); do
                        rp_isInstalled "$idx" && rp_callModule "$idx" remove
                    done
                    rps_logEnd
                } &> >(tee >(gzip --stdout >"$logfilename"))
                rps_printInfo "$logfilename"
                ;;
            *)
                package_setup "$choice"
                ;;
        esac

    done
}

function settings_gui_setup() {
    local default
    while true; do
        local options=()
        local idx
        for idx in "${__mod_idx[@]}"; do
            # show all configuration modules and any installed packages with a gui function
            if [[ "${__mod_section[idx]}" == "config" ]] || rp_isInstalled "$idx" && fnExists "gui_${__mod_id[idx]}"; then
                options+=("$idx" "${__mod_id[$idx]}  - ${__mod_desc[$idx]}" "$idx ${__mod_desc[$idx]}")
            fi
        done

        local cmd=(dialog --backtitle "$__backtitle" --cancel-label "Back" --item-help --help-button --default-item "$default" --menu "Choose an option" 22 76 16)

        local choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
        [[ -z "$choice" ]] && break
        if [[ "${choice[@]:0:4}" == "HELP" ]]; then
            choice="${choice[@]:5}"
            default="${choice/%\ */}"
            choice="${choice#* }"
            printMsgs "dialog" "$choice"
            continue
        fi

        [[ -z "$choice" ]] && break

        default="$choice"

        local logfilename
        __ERRMSGS=()
        __INFMSGS=()
        rps_logInit
        {
            rps_logStart
            if fnExists "gui_${__mod_id[choice]}"; then
                rp_callModule "$choice" depends
                rp_callModule "$choice" gui
            else
                rp_callModule "$choice"
            fi
            rps_logEnd
        } &> >(tee >(gzip --stdout >"$logfilename"))
        rps_printInfo "$logfilename"
    done
}

function update_packages_setup() {
    local idx
    for idx in ${__mod_idx[@]}; do
        if rp_isInstalled "$idx"; then
            rp_installModule "$idx"
        fi
    done
}

function update_packages_gui_setup() {
    local update="$1"
    if [[ "$update" != "update" ]]; then
        dialog --defaultno --yesno "Are you sure you want to update installed packages?" 22 76 2>&1 >/dev/tty || return 1
        updatescript_setup
        # restart at post_update and then call "update_packages_gui_setup update" afterwards
        exec "$scriptdir/retropie_packages.sh" setup post_update update_packages_gui_setup update
    fi

    local logfilename
    __ERRMSGS=()
    __INFMSGS=()
    rps_logInit
    {
        rps_logStart
        dialog --yesno "Would you like to update the underlying OS packages (eg kernel etc) ?" 22 76 2>&1 >/dev/tty && apt_upgrade_raspbiantools
        update_packages_setup
        rps_logEnd
    } &> >(tee >(gzip --stdout >"$logfilename"))

    rps_printInfo "$logfilename"
    gui_setup
}

function quick_install_setup() {
    for idx in $(rp_getSectionIds core) $(rp_getSectionIds main); do
        if rp_hasBinaries; then
            rp_installModule "$idx"
        else
            rp_callModule "$idx"
        fi
    done
}

function packages_gui_setup() {
    local section
    local default
    local options=()

    options+=(
        I "Quick install" "I This will install all packages from Core and Main which gives a basic RetroPie install. Further packages can then be installed later from the Optional and Experimental sections. If binaries are available they will be used, alternatively packages will be built from source - which will take longer."
        U "Update all installed packages" "U Update all currently installed packages"
    )

    for section in core main opt driver exp; do
        options+=($section "Manage ${__sections[$section]} packages" "$section Choose top install/update/configure packages from the ${__sections[$section]}")
    done

    local cmd
    while true; do
        cmd=(dialog --backtitle "$__backtitle" --cancel-label "Back" --item-help --help-button --default-item "$default" --menu "Choose an option" 22 76 16)

        local choice
        choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
        [[ -z "$choice" ]] && break
        if [[ "${choice[@]:0:4}" == "HELP" ]]; then
            choice="${choice[@]:5}"
            default="${choice/%\ */}"
            choice="${choice#* }"
            printMsgs "dialog" "$choice"
            continue
        fi
        default="$choice"
        case "$choice" in
            I)
                dialog --defaultno --yesno "Are you sure you want to do a quick install?" 22 76 2>&1 >/dev/tty || continue
                quick_install_setup
                ;;
            U)
                update_packages_gui_setup
                ;;
            *)
                section_gui_setup "$choice"
                ;;
        esac

    done
}

function uninstall_setup()
{
    dialog --defaultno --yesno "Are you sure you want to uninstall RetroPie?" 22 76 2>&1 >/dev/tty || return 0
    printMsgs "dialog" "This feature is new, and you still may need to remove some files manually, such as symlinks for some emulators created in $home"
    dialog --defaultno --yesno "Are you REALLY sure you want to uninstall RetroPie?\n\n$rootdir and $datadir will be removed - this includes your RetroPie configurations and ROMs." 22 76 2>&1 >/dev/tty || return 0
    clear
    printHeading "Uninstalling RetroPie"
    for idx in "${__mod_idx[@]}"; do
        rp_isInstalled "$idx" && rp_callModule $idx remove
    done
    rm -rfv "$rootdir"
    rm -rfv "$datadir"
    if dialog --defaultno --yesno "Do you want to remove all the system packages that RetroPie depends on? \n\nWARNING: this will remove packages like SDL even if they were installed before you installed RetroPie - it will also remove any package configurations - such as those in /etc/samba for Samba.\n\nIf unsure choose No (selected by default)." 22 76 2>&1 >/dev/tty; then
        clear
        # remove all dependencies
        for idx in "${__mod_idx[@]}"; do
            rp_isInstalled "$idx" && rp_callModule "$idx" depends remove
        done
    fi
}

function reboot_setup()
{
    clear
    reboot
}

# retropie-setup main menu
function gui_setup() {
    depends_setup
    local default
    while true; do
        pushd "$scriptdir" >/dev/null
        local commit=$(git log -1 --pretty=format:"%cr (%h)")
        popd >/dev/null

        cmd=(dialog --backtitle "$__backtitle" --title "RetroPie-Setup Script" --cancel-label "Exit" --item-help --help-button --default-item "$default" --menu "Version: $__version\nLast Commit: $commit" 22 76 16)
        options=(
            P "Manage Packages"
            "P Install/Remove and Configure the various components of RetroPie, including emulators, ports, and controller drivers."

            S "Setup / Tools"
            "S Configuration Tools and additional setup. Any components of RetroPie that have configuration will also appear here after install."

            X "Uninstall RetroPie"
            "X Uninstall RetroPie completely."

            U "Update RetroPie-Setup script"
            "U Update this RetroPie-Setup script. Note that RetroPie-Setup is constantly updated - the version numbers were introduced primarily for the pre-made images we provided, but we now display a version in this menu as a guide. If you update the RetroPie-Setup script after downloading a pre-made image, you may get a higher version number or a -dev release. This does not mean the software is unstable, it just means we are working on changes for the next version, when we will create a new image."

            R "Perform Reboot"
            "R Reboot your machine."
        )

        choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
        [[ -z "$choice" ]] && break

        if [[ "${choice[@]:0:4}" == "HELP" ]]; then
            choice="${choice[@]:5}"
            default="${choice/%\ */}"
            choice="${choice#* }"
            printMsgs "dialog" "$choice"
            continue
        fi
        clear
        case "$choice" in
            P)
                packages_gui_setup
                ;;
            S)
                settings_gui_setup
                ;;
            X)
                uninstall_setup
                ;;
            U)
                updatescript_setup && exec "$scriptdir/retropie_packages.sh" setup post_update gui_setup
                ;;
            R)
                dialog --defaultno --yesno "Are you sure you want to reboot?" 22 76 2>&1 >/dev/tty || continue
                reboot_setup
                ;;
        esac
    done
    clear
}
