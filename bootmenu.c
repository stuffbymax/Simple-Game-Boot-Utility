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
#define MAX_CATS 1

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

/* -------------------------------------------------- */

static SDL_Renderer *ren = NULL;
static TTF_Font *font = NULL;
static Category cats[MAX_CATS];
static int cur_cat = 0;
static int cur_item = 0;

/* -------------------------------------------------- */
/* Icon loading */

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
        if (!strstr(e->d_name, ".desktop"))
            continue;

        char path[512];
        snprintf(path, sizeof(path), "%s/%s", dir, e->d_name);

        FILE *f = fopen(path, "r");
        if (!f) continue;

        char line[256];
        char name[64] = "";
        char exec[256] = "";
        char icon[128] = "";
        int is_term = 0;
        int nodisplay = 0;

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
}

/* -------------------------------------------------- */
/* Rendering */

static void draw_text(const char *t, int x, int y, int size, int alpha) {
    SDL_Color col = {200, 210, 255, alpha};
    TTF_Font *f = TTF_OpenFont(
        "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
        size
    );
    if (!f) return;

    SDL_Surface *s = TTF_RenderUTF8_Blended(f, t, col);
    if (!s) {
        TTF_CloseFont(f);
        return;
    }

    SDL_Texture *tx = SDL_CreateTextureFromSurface(ren, s);
    SDL_Rect r = {x, y, s->w, s->h};

    SDL_RenderCopy(ren, tx, NULL, &r);

    SDL_DestroyTexture(tx);
    SDL_FreeSurface(s);
    TTF_CloseFont(f);
}

static void render(void) {
    SDL_SetRenderDrawColor(ren, 8, 14, 28, 255);
    SDL_RenderClear(ren);

    /* Category title */
    draw_text(
        cats[cur_cat].name,
        100,
        80,
        40,
        255
    );

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
                120,
                y,
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
    if (SDL_Init(SDL_INIT_VIDEO) < 0)
        return 1;

    if (TTF_Init() < 0)
        return 1;

    IMG_Init(IMG_INIT_PNG);

    SDL_Window *win = SDL_CreateWindow(
        "BootMenu",
        SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED,
        W,
        H,
        SDL_WINDOW_FULLSCREEN
    );

    ren = SDL_CreateRenderer(
        win,
        -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC
    );

    init_menu();

    int run = 1;
    SDL_Event e;

    while (run) {
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_QUIT)
                run = 0;
        }

        render();
        SDL_Delay(16);
    }

    SDL_DestroyRenderer(ren);
    SDL_DestroyWindow(win);
    IMG_Quit();
    TTF_Quit();
    SDL_Quit();
    return 0;
}
