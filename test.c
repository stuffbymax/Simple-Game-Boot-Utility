#include <ncurses.h>
#include <string.h>

#define MAX_ITEMS 20

const char *menu_items[MAX_ITEMS] = {
    "RetroArch", "Desktop: GNOME", "Desktop: KDE", "Terminal", "Reboot", "Shutdown"
};
int n_items = 6;

int main() {
    initscr();
    cbreak();
    noecho();
    keypad(stdscr, TRUE);  // Enable arrow keys
    curs_set(0);

    int current = 0;
    int ch;

    while (1) {
        clear();

        // Draw header
        attron(A_BOLD);
        mvprintw(0, 0, "┌───────────────────────────────────────────────┐");
        mvprintw(1, 0, "│              SIMPLE GAME BOOT                 │");
        mvprintw(2, 0, "│           Arch | Debian | Ubuntu | Fedora     │");
        mvprintw(3, 0, "└───────────────────────────────────────────────┘");
        attroff(A_BOLD);

        // Draw horizontal menu
        int x = 2, y = 5;
        for (int i = 0; i < n_items; i++) {
            if (i == current) attron(A_REVERSE | A_BOLD);  // Highlight current
            mvprintw(y, x, " %s ", menu_items[i]);
            if (i == current) attroff(A_REVERSE | A_BOLD);
            x += strlen(menu_items[i]) + 4;
        }

        // Prompt
        mvprintw(y+2, 2, "Use Left/Right arrows to navigate, Enter to select.");

        refresh();

        // Read input
        ch = getch();
        if (ch == KEY_LEFT) current--;
        else if (ch == KEY_RIGHT) current++;
        else if (ch == 10) { // Enter key
            // Execute action here (system("retroarch") etc.)
        }
        else if (ch == 'q') break;

        // Wrap-around
        if (current < 0) current = n_items - 1;
        if (current >= n_items) current = 0;
    }

    endwin();
    return 0;
}
