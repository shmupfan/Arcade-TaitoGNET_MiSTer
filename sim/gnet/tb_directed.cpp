// Directed tests for rtl/gnet/gnet_fc.sv: behaviour the game traces never
// reach (no game data needed; a synthetic card and key).
//   flash: read identifier per chip, program AND semantics, erase block
//          sizes (E28F400B boot/parameter/main), busy duration per preset
//   ATA:   lock (commands fail while locked, DRDY clear), wrong key relock
//          (MAME), unknown command ABRT, IDENTIFY, multi-sector LBA read,
//          WRITE SECTORS and dirty map, CHS read, SRST sequence
//   RF5C296: 00h, 01h, 3Ah reads, card reset hold
//   control: control/control3 readback, 0x1fb70000, watchdog expiry
// Build: VARIANT=dir FLASH_PRESET=n sim/gnet/build_directed.sh
#include "Vgnet_fc.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <vector>

#ifndef CLK_HZ
#define CLK_HZ 67737600ull
#endif
#ifndef PRESET
#define PRESET 1
#endif
#ifndef WD_S
#define WD_S 8   // MB3773 period in s (gnet_ctrl.sv WD_TIMEOUT_S default)
#endif

static Vgnet_fc *top;
static uint64_t cyc = 0;
static std::vector<uint16_t> flash[5];
static const uint32_t FW[5] = {1u << 20, 1u << 18, 1u << 20, 1u << 20, 1u << 20};
static std::vector<uint8_t> card(80000 * 512);
static int fails = 0, checks = 0;
static int wd_pulses = 0;
static int kick_pulses = 0, sec_pulses = 0;   // debug taps (docs/hw_debug_overlay.md)

static void tick() {
    top->clk = 0; top->eval();
    if (top->fmem_req && !top->fmem_ack) {
        unsigned c = top->fmem_chip, a = top->fmem_addr & (FW[c] - 1);
        if (top->fmem_we) flash[c][a] = top->fmem_wdata; else top->fmem_rdata = flash[c][a];
        top->fmem_ack = 1;
    } else top->fmem_ack = 0;
    if (top->cmem_req && !top->cmem_ack) {
        uint64_t a = (uint64_t)top->cmem_addr * 2;
        if (top->cmem_we) { card[a] = top->cmem_wdata; card[a + 1] = top->cmem_wdata >> 8; }
        else top->cmem_rdata = card[a] | card[a + 1] << 8;
        top->cmem_ack = 1;
    } else top->cmem_ack = 0;
    top->clk = 1; top->eval();
    if (top->wd_reset) wd_pulses++;
    if (top->dbg_wd_kick) kick_pulses++;
    if (top->dbg_sec_cmd) sec_pulses++;
    cyc++;
}
static void run(uint64_t n) { for (uint64_t i = 0; i < n; i++) tick(); }
static void run_us(double us) { run((uint64_t)(us * CLK_HZ / 1e6)); }
static uint32_t acc(bool we, uint32_t addr, uint32_t data, uint8_t be) {
    top->cpu_req = 1; top->cpu_we = we; top->cpu_addr = addr - 0x1f000000u; top->cpu_be = be; top->cpu_wdata = data;
    tick(); top->cpu_req = 0;
    while (!top->cpu_ack) tick();
    uint32_t r = top->cpu_rdata; tick(); return r;
}
static void w16(uint32_t a, uint16_t v) { acc(true, a & ~3u, (a & 2) ? (uint32_t)v << 16 : v, (a & 2) ? 0xc : 0x3); }
static uint16_t r16(uint32_t a) { uint32_t r = acc(false, a & ~3u, 0, (a & 2) ? 0xc : 0x3); return (a & 2) ? r >> 16 : r & 0xffff; }
static void w8(uint32_t a, uint8_t v) { acc(true, a & ~3u, (uint32_t)v << (8 * (a & 3)), 1 << (a & 3)); }
static uint8_t r8(uint32_t a) { return acc(false, a & ~3u, 0, 1 << (a & 3)) >> (8 * (a & 3)); }
static void check(const char *what, uint32_t got, uint32_t want) {
    checks++;
    if (got != want) { fails++; printf("FAIL %-48s got %08x want %08x\n", what, got, want); }
}
static const uint32_t ATA = 0x1fb00000;
static uint8_t st() { return r8(ATA + 7); }
static void exca(uint8_t i, uint8_t v) { w8(ATA + 0x3e0, i); w8(ATA + 0x3e1, v); }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    for (int c = 0; c < 5; c++) flash[c].assign(FW[c], 0xffff);
    for (size_t i = 0; i < card.size(); i++) card[i] = (uint8_t)(i * 7 + (i >> 9));
    top = new Vgnet_fc;
    top->rst = 1; top->jp1 = 0; top->card_present = 1; top->cpu_req = 0; top->key_valid = 1; top->dirty_clear = 0;
    const uint8_t key[5] = {0x12, 0x34, 0x56, 0x78, 0x9a};
    auto meta = [&](unsigned a, uint8_t v) { top->meta_we = 1; top->meta_addr = a; top->meta_wdata = v; tick(); };
    for (unsigned i = 0; i < 512; i++) meta(i, (uint8_t)(i ^ 0x5a));
    for (unsigned i = 0; i < 256; i++) meta(0x200 + i, i < 16 ? (uint8_t)(0x10 + i) : 0xff);
    for (unsigned i = 0; i < 5; i++) meta(0x300 + i, key[i]);
    top->meta_we = 0;
    run(20000); top->rst = 0; run(10);

    // ---- control
    check("control reset value", r16(0x1fb40000), 0x0010);
    w16(0x1fb40000, 0x00e4); check("control readback", r16(0x1fb40000), 0x00e4);
    check("no kick: CK rose (10h to E4h)", kick_pulses, 0);
    w8(0x1fb40000, 0xc4); check("kick on CK falling edge", kick_pulses, 1);
    check("debug tap: control value", top->dbg_ctrl, 0xc4);
    w8(0x1fb40000, 0xe4); check("no kick on CK rising edge", kick_pulses, 1);
    check("debug tap: control value back", top->dbg_ctrl, 0xe4);
    check("zoom_reset output", top->zoom_reset, 0);
    w8(0x1fa30000, 0x5a); check("control3 readback", r8(0x1fa30000), 0x5a);
    check("0x1fb70000 reads 2", r16(0x1fb70000), 0x0002);
    w16(0x1fb40000, 0x0000);   // back to bank 0

    // ---- flash: identifiers
    w16(0x1f000000, 0x9090); check("U30 maker", r16(0x1f000000), 0x00b0); check("U30 device", r16(0x1f000002), 0x00d0);
    w16(0x1f000000, 0x00ff);
    w16(0x1f300000, 0x9090); check("U27 maker", r16(0x1f300000), 0x0089); check("U27 device", r16(0x1f300002), 0x4471);
    w16(0x1f300000, 0x00ff);
    w16(0x1fb40000, 0x0004);   // bank 1: waves
    for (int k = 0; k < 3; k++) {
        uint32_t b = 0x1f000000 + k * 0x200000;
        w16(b, 0x9090); check("wave maker", r16(b), 0x00b0); check("wave device", r16(b + 2), 0x00d0); w16(b, 0xff);
    }
    w16(0x1fb40000, 0x0000);
    // ---- program (AND) and status
    w16(0x1f000100, 0x4040); w16(0x1f000100, 0x1234);
    check("status after program", r16(0x1f000000) & 0xff, PRESET == 1 ? 0x80 : 0x00);
    run_us(25); check("status after 25 us", r16(0x1f000000) & 0xff, 0x80);
    w16(0x1f000000, 0x00ff); check("programmed word", r16(0x1f000100), 0x1234);
    w16(0x1f000100, 0x4040); w16(0x1f000100, 0xff0f); run_us(25); w16(0x1f000000, 0xff);
    check("second program ANDs (datasheet)", r16(0x1f000100), 0x1204);
    // ---- erase timing and block size (U30 64 KB)
    w16(0x1f010000, 0x2020); w16(0x1f010000, 0xd0d0);
    check("status during erase", r16(0x1f010000) & 0xff, 0x00);
    double t_er = PRESET == 1 ? 1000000.0 : PRESET == 2 ? 560000.0 : 340000.0;
    run_us(t_er - 50); check("still busy just before erase time", r16(0x1f010000) & 0xff, 0x00);
    run_us(100); check("ready after erase time", r16(0x1f010000) & 0xff, 0x80);
    // ---- E28F400B blocks: program words, erase the 2nd parameter block (8 KB at 0x6000)
    for (uint32_t off : {0x5ffeu, 0x6000u, 0x7ffeu, 0x8000u}) { w16(0x1f300000 + off, 0x4040); w16(0x1f300000 + off, 0x0000); }
    w16(0x1f306000, 0x2020); w16(0x1f306000, 0xd0d0); run_us(300000 + 100); w16(0x1f300000, 0xff);
    check("U27 0x5ffe kept", r16(0x1f305ffe), 0x0000); check("U27 0x6000 erased", r16(0x1f306000), 0xffff);
    check("U27 0x7ffe erased", r16(0x1f307ffe), 0xffff); check("U27 0x8000 kept", r16(0x1f308000), 0x0000);

    // ---- RF5C296
    check("ExCA 00h", (w8(ATA + 0x3e0, 0x00), r8(ATA + 0x3e1)), 0x83);
    check("ExCA 3Ah", (w8(ATA + 0x3e0, 0x3a), r8(ATA + 0x3e1)), 0x32);
    exca(0x02, 0xb0);
    check("ExCA 01h (power, card present)", (w8(ATA + 0x3e0, 0x01), r8(ATA + 0x3e1)), 0x6f);
    check("card held in reset at power-on", top->card_reset, 1);
    exca(0x03, 0x40); check("card released", top->card_reset, 0);
    check("ATA busy during reset", st() & 0x80, 0x80);
    run_us(4100);
    check("ATA after reset: DSC, no DRDY (locked)", st(), 0x10);
    check("signature sector count", r8(ATA + 2), 1);
    check("diagnostic error code", r8(ATA + 1), 1);

    // ---- lock
    w8(ATA + 6, 0xe0); w8(ATA + 7, 0xec);
    check("command while locked: ERR, DRDY clear", st(), 0x11);
    check("error 00h while locked", r8(ATA + 1), 0x00);
    check("lock status 0x201", r16(0x1f200402) & 0xff, 1);
    for (int i = 0; i < 9; i++) w16(0x1f200500 + 2 * i, i < 5 ? key[i] : 0);
    check("unlocked", r16(0x1f200402) & 0xff, 0);
    w16(0x1f200500, 0x00);   // wrong byte relocks (MAME)
    check("wrong key relocks", r16(0x1f200402) & 0xff, 1);
    w16(0x1f200500, key[0]);
    check("CIS byte 3", r16(0x1f200006), 0x0013);
    check("pin replacement", r16(0x1f200204), 0x002e);

    // ---- IDENTIFY
    w8(ATA + 7, 0xec);
    check("IDENTIFY busy", st() & 0x80, 0x80);
    run_us(11);
    check("IDENTIFY DRQ", st(), 0x58);
    check("IDENTIFY word 0", r16(ATA), 0x5a5a ^ 0x0100 ^ 0x0000 ? (uint16_t)((0x01 ^ 0x5a) << 8 | (0x00 ^ 0x5a)) : 0);
    for (int i = 1; i < 256; i++) r16(ATA);
    check("IDENTIFY done", st(), 0x50);

    // ---- unknown command
    w8(ATA + 7, 0xc4);
    check("unknown command ERR", st(), 0x51); check("ABRT", r8(ATA + 1), 0x04);

    // ---- READ SECTORS, 3 sectors from LBA 1000
    w8(ATA + 2, 3); w8(ATA + 3, 1000 & 0xff); w8(ATA + 4, 1000 >> 8); w8(ATA + 5, 0); w8(ATA + 6, 0xe0);
    w8(ATA + 7, 0x20);
    int bad = 0;
    for (int s = 0; s < 3; s++) {
        while (st() & 0x80) ;
        if ((st() & 0x08) == 0) bad++;
        for (int i = 0; i < 256; i++) {
            uint64_t a = (uint64_t)(1000 + s) * 512 + 2 * i;
            if (r16(ATA) != (card[a] | card[a + 1] << 8)) bad++;
        }
    }
    check("3-sector LBA read data", bad, 0);
    check("LBA registers advanced to last sector", r8(ATA + 3), (1002) & 0xff);
    check("status after read", st(), 0x50);

    // ---- WRITE SECTORS, 2 sectors at LBA 50000, byte transfers on the first
    w8(ATA + 2, 2); w8(ATA + 3, 50000 & 0xff); w8(ATA + 4, (50000 >> 8) & 0xff); w8(ATA + 5, 0); w8(ATA + 6, 0xe0);
    w8(ATA + 7, 0x30);
    check("write DRQ", st(), 0x58);
    for (int i = 0; i < 512; i++) w8(ATA, (uint8_t)(0xa0 + i));
    check("write busy after a sector", st() & 0x80, 0x80);
    run_us(110);
    check("second sector DRQ", st(), 0x58);
    for (int i = 0; i < 256; i++) w16(ATA, (uint16_t)(0x1100 + i));
    run_us(110);
    check("write done", st(), 0x50);
    bad = 0;
    for (int i = 0; i < 512; i++) if (card[50000ull * 512 + i] != (uint8_t)(0xa0 + i)) bad++;
    for (int i = 0; i < 256; i++) if ((card[50001ull * 512 + 2 * i] | card[50001ull * 512 + 2 * i + 1] << 8) != 0x1100 + i) bad++;
    check("written sector data", bad, 0);
    top->dirty_raddr = 50000 / 8; tick(); tick();
    check("dirty hunk set", top->dirty_rdata, 1);
    top->dirty_raddr = 50000 / 8 + 1; tick(); tick();
    check("next hunk clean", top->dirty_rdata, 0);

    // ---- CHS read: cylinder 2, head 3, sector 5 with 16 heads, 50 sectors
    w8(ATA + 2, 1); w8(ATA + 3, 5); w8(ATA + 4, 2); w8(ATA + 5, 0); w8(ATA + 6, 0xa3); w8(ATA + 7, 0x20);
    while (st() & 0x80) ;
    { uint32_t lba = (2 * 16 + 3) * 50 + 5 - 1; uint64_t a = (uint64_t)lba * 512;
      check("CHS read first word", r16(ATA), card[a] | card[a + 1] << 8); for (int i = 1; i < 256; i++) r16(ATA); }

    check("debug tap: sector commands (READ x2, WRITE x1; ECh, C4h not counted)", sec_pulses, 3);

    // ---- SRST
    w8(ATA + 14, 0x04); check("SRST busy", r8(ATA + 14) & 0x80, 0x80);
    w8(ATA + 14, 0x00); run_us(2100);
    check("after SRST: DRDY DSC", st(), 0x50);

    // ---- watchdog: no kicks for the timeout
    int before = wd_pulses, kicks0 = kick_pulses; run((uint64_t)CLK_HZ * WD_S + 1000);
    check("watchdog pulse after one period (WD_S s)", wd_pulses - before >= 1, 1);
    check("no kick while the watchdog ran out", kick_pulses - kicks0, 0);
    check("kicks: C4h, then E4h to 00h at the bank switch", kick_pulses, 2);

    // ---- empty slot (card_present = 0): MAME's empty pccard slot reads FFFFh
    top->card_present = 0;
    check("no card: task file status", r8(ATA + 7), 0xff);
    check("no card: data port", r16(ATA), 0xffff);
    check("no card: attribute memory", r16(0x1f200000), 0xffff);
    w8(ATA + 0x3e0, 0x01);
    check("no card: ExCA 01h card detect bits 0", r8(ATA + 0x3e1) & 0x0c, 0x00);
    top->card_present = 1;
    check("card back: ExCA 01h card detect bits", r8(ATA + 0x3e1) & 0x0c, 0x0c);

    printf("directed: %d checks, %d failures (preset %d)\n", checks, fails, PRESET);
    delete top;
    return fails ? 1 : 0;
}
