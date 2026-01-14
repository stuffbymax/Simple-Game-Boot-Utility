#include <ncurses.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <stdio.h>

#define MAX_ITEMS 50
#define ITEM_NAME_LEN 128

typedef struct {
    char name[ITEM_NAME_LEN];
    char exec[ITEM_NAME_LEN];
} MenuItem;

MenuItem menu[MAX_ITEMS];
int n_items = 0;

// Auto-detect DEs/WMs
void detect_sessions() {
    const char *paths[] = {"/usr/share/xsessions", "/usr/share/wayland-sessions"};
    for (int p = 0; p < 2; p++) {
        DIR *d = opendir(paths[p]);
        if (!d) continue;
        struct dirent *entry;
        while ((entry = readdir(d)) != NULL) {
            if (strstr(entry->d_name, ".desktop")) {
                char fullpath[256];
                snprintf(fullpath, sizeof(fullpath), "%s/%s", paths[p], entry->d_name);
                FILE *f = fopen(fullpath, "r");
                if (!f) continue;

                char line[256];
                char name[ITEM_NAME_LEN] = "";
                char exec[ITEM_NAME_LEN] = "";
                while (fgets(line, sizeof(line), f)) {
                    if (strncmp(line, "Name=", 5) == 0) {
                        strncpy(name, line + 5, ITEM_NAME_LEN);
                        name[strcspn(name, "\n")] = 0; // remove newline
                    }
                    if (strncmp(line, "Exec=", 5) == 0) {
                        strncpy(exec, line + 5, ITEM_NAME_LEN);
                        exec[strcspn(exec, "\n")] = 0;
                    }
                }
                fclose(f);

                if (strlen(name) > 0 && strlen(exec) > 0 && n_items < MAX_ITEMS) {
                    strncpy(menu[n_items].name, name, ITEM_NAME_LEN);
                    strncpy(menu[n_items].exec, exec, ITEM_NAME_LEN);
                    n_items++;
                }
            }
        }
        closedir(d);
    }
}

// Detect RetroArch
void detect_retroarch() {
    if (system("command -v retroarch >/dev/null 2>&1") == 0) {
        strncpy(menu[n_items].name, "RetroArch", ITEM_NAME_LEN);
        strncpy(menu[n_items].exec, "retroarch", ITEM_NAME_LEN);
        n_items++;
    }
}

// Add Terminal, Reboot, Shutdown
void add_misc_items() {
    strncpy(menu[n_items].name, "Terminal", ITEM_NAME_LEN);
    strncpy(menu[n_items].exec, "terminal", ITEM_NAME_LEN);
    n_items++;

    strncpy(menu[n_items].name, "Reboot", ITEM_NAME_LEN);
    strncpy(menu[n_items].exec, "reboot", ITEM_NAME_LEN);
    n_items++;

    strncpy(menu[n_items].name, "Shutdown", ITEM_NAME_LEN);
    strncpy(menu[n_items].exec, "shutdown", ITEM_NAME_LEN);
    n_items++;
}

// Draw horizontal XMB menu
void draw_menu(int current) {
    clear();
    attron(A_BOLD);
    mvprintw(0, 0, "┌───────────────────────────────────────────────┐");
    mvprintw(1, 0, "│              SIMPLE GAME BOOT                 │");
    mvprintw(2, 0, "│           Arch | Debian | Ubuntu | Fedora     │");
    mvprintw(3, 0, "└───────────────────────────────────────────────┘");
    attroff(A_BOLD);

    int x = 2, y = 5;
    for (int i = 0; i < n_items; i++) {
        if (i == current) attron(A_REVERSE | A_BOLD);
        mvprintw(y, x, " %s ", menu[i].name);
        if (i == current) attroff(A_REVERSE | A_BOLD);
        x += strlen(menu[i].name) + 4;
    }
    mvprintw(y + 2, 2, "Use Left/Right arrows to navigate, Enter to select, q to quit.");
    refresh();
}

// Execute selected item
void execute_item(MenuItem *item) {
    if (strcmp(item->exec, "terminal") == 0) {
        endwin();
        system("$SHELL");
    } else if (strcmp(item->exec, "reboot") == 0) {
        endwin();
        system("sudo reboot");
    } else if (strcmp(item->exec, "shutdown") == 0) {
        endwin();
        system("sudo shutdown now");
    } else {
        endwin();
        char cmd[256];
        snprintf(cmd, sizeof(cmd), "%s", item->exec);
        system(cmd);
    }
}

int main() {
    // Auto-detect items
    detect_retroarch();
    detect_sessions();
    add_misc_items();

    // Init ncurses
    initscr();
    cbreak();
    noecho();
    keypad(stdscr, TRUE);
    curs_set(0);

    int current = 0;
    int ch;

    while (1) {
        draw_menu(current);

        ch = getch();
        if (ch == KEY_LEFT) current--;
        else if (ch == KEY_RIGHT) current++;
        else if (ch == 10) { // Enter
            execute_item(&menu[current]);
        }
        else if (ch == 'q' || ch == 'Q') break;

        // Wrap-around
        if (current < 0) current = n_items - 1;
        if (current >= n_items) current = 0;
    }

    endwin();
    return 0;
}
