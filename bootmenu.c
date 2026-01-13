#define _GNU_SOURCE
#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <SDL2/SDL_image.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define W 1280
#define H 720
#define MAX_ITEMS 32
#define MAX_CATS 3

typedef struct {
    char label[64];
    char exec[256];
    SDL_Texture *icon;
} Item;

typedef struct {
    char name[32];
    Item items[MAX_ITEMS];
    int count;
} Category;

static SDL_Renderer *ren;
static TTF_Font *font;

static Category cats[MAX_CATS];
static int cur_cat = 0, cur_item = 0;

/* -------------------------------------------------- */

static void spawn(const char *cmd) {
    if (fork() == 0) {
        setsid();
        execl("/bin/sh", "sh", "-c", cmd, NULL);
        _exit(1);
    }
}

/* -------------------------------------------------- */
/* Icon resolution */

static SDL_Texture *load_icon(const char *name) {
    const char *paths[] = {
        "/usr/share/icons/hicolor/128x128/apps/",
        "/usr/share/pixmaps/",
        NULL
    };

    char path[512];
    for (int i = 0; paths[i]; i++) {
        snprintf(path, sizeof(path), "%s%s.png", paths[i], name);
        if (access(path, R_OK) == 0) {
            SDL_Surface *s = IMG_Load(path);
            if (!s) continue;
            SDL_Texture *t = SDL_CreateTextureFromSurface(ren, s);
            SDL_FreeSurface(s);
            return t;
        }
    }
    return NULL;
}

/* -------------------------------------------------- */
/* Terminal detection */

static void scan_terminals(const char *dir, Category *c) {
    DIR *d = opendir(dir);
    if (!d) return;

    struct dirent *e;
    while ((e = readdir(d)) && c->count < MAX_ITEMS) {
        if (!strstr(e->d_name, ".desktop")) continue;

        char path[512];
        snprintf(path, sizeof(path), "%s/%s", dir, e->d_name);

        FILE *f = fopen(path, "r");
        if (!f) continue;

        char line[256], name[64] = "", exec[256] = "", icon[128] = "";
        int is_term = 0, nodisplay = 0;

        while (fgets(line, sizeof(line), f)) {
            if (sscanf(line, "Name=%63[^\n]", name) == 1) {}
            if (sscanf(line, "Exec=%255[^\n]", exec) == 1) {}
            if (sscanf(line, "Icon=%127[^\n]", icon) == 1) {}
            if (strstr(line, "Terminal=true")) is_term = 1;
            if (strstr(line, "NoDisplay=true")) nodisplay = 1;
        }
        fclose(f);

        if (is_term && !nodisplay && *name && *exec) {
            Item *it = &c->items[c->count++];
            strcpy(it->label, name);
            strcpy(it->exec, exec);
            it->icon = *icon ? load_icon(icon) : NULL;
        }
    }
    closedir(d);
}

/* -------------------------------------------------- */

static void init_menu(void) {
    strcpy(cats[0].name, "Terminals");
    scan_terminals("/usr/share/applications", &cats[0]);
    scan_terminals("/usr/local/share/applications", &cats[0]);

    strcpy(cats[1].name, "Games");
    strcpy(cats[1].items[0].label, "RetroArch");
    strcpy(cats[1].items[0].exec, "retroarch -f");
    cats[1].items[0].icon = load_icon("retroarch");
    cats[1].count = 1;

    strcpy(cats[2].name, "Power");
    strcpy(cats[2].items[0].label, "Reboot");
    strcpy(cats[2].items[0].exec, "reboot");
    strcpy(cats[2].items[1].label, "Shutdown");
    strcpy(cats[2].items[1].exec, "shutdown now");
    cats[2].count = 2;
}

/* -------------------------------------------------- */

static void draw_text(const char *t, int x, int y, int size, int a) {
    SDL_Color c = {200, 210, 255, a};
    SDL_Surface *s = TTF_RenderUTF8_Blended(font, t, c);
    if (!s) return;
    SDL_Texture *tx = SDL_CreateTextureFromSurface(ren, s);
    SDL_Rect r = {x, y, s->w, s->h};
    SDL_RenderCopy(ren, tx, NULL, &r);
    SDL_DestroyTexture(tx);
    SDL_FreeSurface(s);
}

/* -------------------------------------------------- */

static void render(void) {
    SDL_SetRenderDrawColor(ren, 8, 14, 28, 255);
    SDL_RenderClear(ren);

    for (int i = 0; i < MAX_CATS; i++) {
        draw_text(
            cats[i].name,
            100 + i * 260,
            80,
            i == cur_cat ? 38 : 28,
            i == cur_cat ? 255 : 130
        );
    }

    Category *c = &cats[cur_cat];
    if (c->count == 0) {
        SDL_RenderPresent(ren);
        return;
    }

    for (int i = 0; i < c->count; i++) {
        int sel = (i == cur_item);
        int y = 200 + i * 56;

        if (c->items[i].icon) {
            SDL_Rect r = {
                120, y,
                sel ? 96 : 80,
                sel ? 96 : 80
            };
            SDL_RenderCopy(ren, c->items[i].icon, NULL, &r);
        }

        draw_text(
            c->items[i].label,
            240,
            y + 16,
            sel ? 32 : 24,
            sel ? 255 : 140
        );
    }

    SDL_RenderPresent(ren);
}

/* -------------------------------------------------- */

int main(void) {
    SDL_Init(SDL_INIT_VIDEO);
    TTF_Init();
    IMG_Init(IMG_INIT_PNG);

    font = TTF_OpenFont(
        "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
        28
    );
    if (!font) {
        fprintf(stderr, "Font error: %s\n", TTF_GetError());
        return 1;
    }

    SDL_Window *w = SDL_CreateWindow(
        "BootMenu",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        W, H, SDL_WINDOW_FULLSCREEN
    );
    ren = SDL_CreateRenderer(w, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);

    init_menu();

    SDL_Event e;
    int run = 1;

    while (run) {
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_QUIT) run = 0;
            if (e.type == SDL_KEYDOWN) {
                switch (e.key.keysym.sym) {
                    case SDLK_LEFT:  cur_cat = (cur_cat + MAX_CATS - 1) % MAX_CATS; cur_item = 0; break;
                    case SDLK_RIGHT: cur_cat = (cur_cat + 1) % MAX_CATS; cur_item = 0; break;
                    case SDLK_UP:
                        cur_item = (cur_item + c->count - 1) % c->count;
                        break;
                    case SDLK_DOWN:
                        cur_item = (cur_item + 1) % c->count;
                        break;
                    case SDLK_RETURN:
                        spawn(cats[cur_cat].items[cur_item].exec);
                        break;
                    case SDLK_ESCAPE:
                        run = 0;
                        break;
                }
            }
        }
        render();
        SDL_Delay(16);
    }
    return 0;
}
