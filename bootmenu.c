#define _GNU_SOURCE
#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define W 1280
#define H 720
#define MAX_ITEMS 32
#define MAX_CATS 4

typedef struct {
    char label[64];
    char exec[256];
} Item;

typedef struct {
    char name[32];
    Item items[MAX_ITEMS];
    int count;
} Category;

static Category cats[MAX_CATS];
static int cur_cat = 0, cur_item = 0;
static SDL_Renderer *ren;

/* -------------------------------------------------- */

static void spawn(char *const argv[]) {
    if (fork() == 0) {
        setsid();
        execvp(argv[0], argv);
        _exit(1);
    }
}

/* -------------------------------------------------- */
/* Desktop detection */

static void scan_sessions(const char *dir, Category *c) {
    DIR *d = opendir(dir);
    if (!d) return;

    struct dirent *e;
    while ((e = readdir(d)) && c->count < MAX_ITEMS) {
        if (!strstr(e->d_name, ".desktop")) continue;

        char path[256];
        snprintf(path, sizeof(path), "%s/%s", dir, e->d_name);

        FILE *f = fopen(path, "r");
        if (!f) continue;

        char line[256], name[64] = "", exec[256] = "";
        while (fgets(line, sizeof(line), f)) {
            if (!*name && sscanf(line, "Name=%63[^\n]", name) == 1) {}
            if (!*exec && sscanf(line, "Exec=%255[^\n]", exec) == 1) {}
        }
        fclose(f);

        if (*name && *exec) {
            strcpy(c->items[c->count].label, name);
            strcpy(c->items[c->count].exec, exec);
            c->count++;
        }
    }
    closedir(d);
}

/* -------------------------------------------------- */

static void init_menu(void) {
    /* Games */
    strcpy(cats[0].name, "Games");
    strcpy(cats[0].items[0].label, "RetroArch");
    strcpy(cats[0].items[0].exec, "retroarch -f");
    cats[0].count = 1;

    /* Desktop */
    strcpy(cats[1].name, "Desktop");
    scan_sessions("/usr/share/xsessions", &cats[1]);

    /* System */
    strcpy(cats[2].name, "System");
    strcpy(cats[2].items[0].label, "Shell");
    strcpy(cats[2].items[0].exec, "xterm");
    cats[2].count = 1;

    /* Power */
    strcpy(cats[3].name, "Power");
    strcpy(cats[3].items[0].label, "Reboot");
    strcpy(cats[3].items[0].exec, "reboot");
    strcpy(cats[3].items[1].label, "Shutdown");
    strcpy(cats[3].items[1].exec, "shutdown now");
    cats[3].count = 2;
}

/* -------------------------------------------------- */
/* UI */

static void draw_text(const char *t, int x, int y, int size, int alpha) {
    TTF_Font *f = TTF_OpenFont("/usr/share/fonts/TTF/DejaVuSans.ttf", size);
    SDL_Color c = {180, 200, 255, alpha};
    SDL_Surface *s = TTF_RenderUTF8_Blended(f, t, c);
    SDL_Texture *tx = SDL_CreateTextureFromSurface(ren, s);
    SDL_Rect r = {x, y, s->w, s->h};
    SDL_RenderCopy(ren, tx, NULL, &r);
    SDL_FreeSurface(s);
    SDL_DestroyTexture(tx);
    TTF_CloseFont(f);
}

static void render(void) {
    SDL_SetRenderDrawColor(ren, 8, 16, 32, 255);
    SDL_RenderClear(ren);

    for (int i = 0; i < MAX_CATS; i++) {
        draw_text(
            cats[i].name,
            100 + i * 240,
            80,
            i == cur_cat ? 36 : 28,
            i == cur_cat ? 255 : 120
        );
    }

    Category *c = &cats[cur_cat];
    for (int i = 0; i < c->count; i++) {
        draw_text(
            c->items[i].label,
            160,
            180 + i * 46,
            i == cur_item ? 32 : 26,
            i == cur_item ? 255 : 140
        );
    }

    SDL_RenderPresent(ren);
}

/* -------------------------------------------------- */

int main(void) {
    SDL_Init(SDL_INIT_VIDEO);
    TTF_Init();

    SDL_Window *win = SDL_CreateWindow(
        "Boot Menu",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        W, H,
        SDL_WINDOW_FULLSCREEN
    );

    ren = SDL_CreateRenderer(win, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);

    init_menu();

    SDL_Event e;
    int run = 1;

    while (run) {
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_QUIT) run = 0;

            if (e.type == SDL_KEYDOWN) {
                switch (e.key.keysym.sym) {
                    case SDLK_LEFT:
                        cur_cat = (cur_cat + MAX_CATS - 1) % MAX_CATS;
                        cur_item = 0;
                        break;
                    case SDLK_RIGHT:
                        cur_cat = (cur_cat + 1) % MAX_CATS;
                        cur_item = 0;
                        break;
                    case SDLK_UP:
                        cur_item = (cur_item + cats[cur_cat].count - 1)
                                   % cats[cur_cat].count;
                        break;
                    case SDLK_DOWN:
                        cur_item = (cur_item + 1)
                                   % cats[cur_cat].count;
                        break;
                    case SDLK_RETURN: {
                        char *argv[] = {
                            "/bin/sh", "-c",
                            cats[cur_cat].items[cur_item].exec,
                            NULL
                        };
                        spawn(argv);
                        break;
                    }
                    case SDLK_ESCAPE:
                        run = 0;
                        break;
                }
            }
        }
        render();
        SDL_Delay(16);
    }

    SDL_Quit();
    return 0;
}
