import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/member/member_help_bot_intent.dart';

void main() {
  group('memberHelpNeedsLiveEscalation', () {
    test('flags lobby / physical shelf / nego / today hours — not system stok',
        () {
      expect(memberHelpNeedsLiveEscalation('Ada stok rak frame X?'), isTrue);
      expect(memberHelpNeedsLiveEscalation('Ada di rak sekarang?'), isTrue);
      expect(memberHelpNeedsLiveEscalation('Bisa nego harga?'), isTrue);
      expect(memberHelpNeedsLiveEscalation('Lensa saya retak'), isTrue);
      expect(memberHelpNeedsLiveEscalation('Masih buka sekarang?'), isTrue);
      expect(memberHelpNeedsLiveEscalation('Antrean berapa orang?'), isTrue);
      expect(memberHelpNeedsLiveEscalation('Antrean lobby rame?'), isTrue);
      expect(memberHelpNeedsLiveEscalation('Toko lagi rame?'), isFalse);
      expect(memberHelpNeedsLiveEscalation('Antrean lab berapa?'), isFalse);
      expect(memberHelpNeedsLiveEscalation('Cek stok Rayban'), isFalse);
    });

    test('does not flag ordinary FAQ', () {
      expect(memberHelpNeedsLiveEscalation('Bagaimana cara membersihkan?'),
          isFalse);
      expect(memberHelpNeedsLiveEscalation('Berapa poin saya?'), isFalse);
      expect(memberHelpNeedsLiveEscalation('Status pesanan saya'), isFalse);
    });
  });

  group('memberHelpNeedsLabQueue', () {
    test('flags production / lab queue phrases', () {
      expect(memberHelpNeedsLabQueue('Toko lagi rame?'), isTrue);
      expect(memberHelpNeedsLabQueue('Antrean lab berapa?'), isTrue);
      expect(memberHelpNeedsLabQueue('Berapa lama pengerjaan?'), isTrue);
      expect(memberHelpNeedsLabQueue('Antrian kacamata di cabang'), isTrue);
      expect(memberHelpNeedsLabQueue('Sedang dikerjakan berapa?'), isTrue);
      expect(memberHelpNeedsLabQueue('queue di Depok'), isTrue);
    });

    test('does not flag ordinary FAQ', () {
      expect(memberHelpNeedsLabQueue('Bagaimana cara membersihkan?'), isFalse);
      expect(memberHelpNeedsLabQueue('Berapa poin saya?'), isFalse);
    });
  });

  group('memberHelpNeedsStok', () {
    test('flags system stock phrases', () {
      expect(memberHelpNeedsStok('Cek stok Rayban hitam'), isTrue);
      expect(memberHelpNeedsStok('Ada stok frame di Depok?'), isTrue);
      expect(memberHelpNeedsStok('Ready stock lensa progressive?'), isTrue);
      expect(memberHelpNeedsStok('Berapa stok SKU ABC123'), isTrue);
      expect(memberHelpNeedsStok('stock availability Depok'), isTrue);
      expect(memberHelpNeedsStok('stok'), isTrue);
      expect(memberHelpNeedsStok('frame yang ready apa?'), isTrue);
      expect(memberHelpNeedsStok('Apa yang ready di cabang?'), isTrue);
      expect(memberHelpNeedsStok('Ada frame hitam?'), isTrue);
      expect(memberHelpNeedsStok('stock ready'), isTrue);
      expect(memberHelpNeedsStok('stok ready'), isTrue);
    });

    test('does not flag ordinary FAQ', () {
      expect(memberHelpNeedsStok('Bagaimana cara membersihkan?'), isFalse);
      expect(memberHelpNeedsStok('Berapa poin saya?'), isFalse);
      expect(memberHelpNeedsStok('Status pesanan saya'), isFalse);
    });

    test('does not treat physical shelf as system stok', () {
      expect(memberHelpNeedsLiveEscalation('Ada di rak sekarang?'), isTrue);
      expect(memberHelpDetectIntent('Ada di rak sekarang?'),
          MemberHelpIntent.escalateLive);
    });
  });

  group('memberHelpExtractStockQuery', () {
    test('keeps product tokens', () {
      expect(
        memberHelpExtractStockQuery('Cek stok Rayban hitam di Depok'),
        contains('rayban'),
      );
      expect(
        memberHelpExtractStockQuery('Cek stok Rayban hitam di Depok'),
        contains('hitam'),
      );
      expect(memberHelpExtractStockQuery('cek stok'), isEmpty);
      expect(
        memberHelpExtractStockQuery('cek stok Rayban'),
        'rayban',
      );
    });

    test('colloquial “apa aja” fillers → empty query (summary mode)', () {
      expect(memberHelpExtractStockQuery('stok ada apa aja'), isEmpty);
      expect(memberHelpExtractStockQuery('stok apa aja'), isEmpty);
      expect(memberHelpExtractStockQuery('ada stok apa'), isEmpty);
      expect(memberHelpExtractStockQuery('stok ada apa aja dong kak'), isEmpty);
      expect(memberHelpExtractStockQuery('ready stock apa aja sih'), isEmpty);
      expect(memberHelpDetectIntent('stok ada apa aja'), MemberHelpIntent.stok);
    });

    test('strips named cabang tokens so location-only stock → summary', () {
      expect(
        memberHelpExtractStockQuery(
          'stok di Singaparna',
          stripNamedToko: 'singaparna',
        ),
        isEmpty,
      );
      expect(
        memberHelpExtractStockQuery(
          'cek stok Rayban di Singaparna',
          stripNamedToko: 'singaparna',
        ),
        contains('rayban'),
      );
      expect(
        memberHelpExtractStockQuery(
          'cek stok Rayban di Singaparna',
          stripNamedToko: 'singaparna',
        ),
        isNot(contains('singaparna')),
      );
    });
  });

  group('memberHelpWantsWhatsAppContact', () {
    test('flags WA / contact free-text phrases', () {
      expect(memberHelpWantsWhatsAppContact('bagi nomor wa dong'), isTrue);
      expect(memberHelpWantsWhatsAppContact('minta nomor WA cabang'), isTrue);
      expect(memberHelpWantsWhatsAppContact('whatsapp toko'), isTrue);
      expect(memberHelpWantsWhatsAppContact('hubungi cabang'), isTrue);
      expect(memberHelpWantsWhatsAppContact('chat toko dong'), isTrue);
      expect(memberHelpWantsWhatsAppContact('bagi nomor'), isTrue);
      expect(memberHelpWantsWhatsAppContact('contact branch please'), isTrue);
    });

    test('does not flag ordinary FAQ', () {
      expect(memberHelpWantsWhatsAppContact('Bagaimana cara membersihkan?'),
          isFalse);
      expect(memberHelpWantsWhatsAppContact('Berapa poin saya?'), isFalse);
      expect(memberHelpWantsWhatsAppContact('Status pesanan saya'), isFalse);
      expect(memberHelpWantsWhatsAppContact('Alamat cabang Depok'), isFalse);
    });
  });

  group('memberHelpDetectIntent', () {
    test('routes common intents', () {
      expect(
        memberHelpDetectIntent('Cek status pesanan invoice'),
        MemberHelpIntent.orderStatus,
      );
      expect(
        memberHelpDetectIntent('Poin dan grade saya'),
        MemberHelpIntent.pointsGrade,
      );
      expect(
        memberHelpDetectIntent('Alamat cabang Depok'),
        MemberHelpIntent.storeInfo,
      );
      expect(
        memberHelpDetectIntent('Syarat garansi'),
        MemberHelpIntent.careWarranty,
      );
      expect(
        memberHelpDetectIntent('Hubungi WA toko'),
        MemberHelpIntent.contactWa,
      );
      expect(
        memberHelpDetectIntent('bagi nomor wa dong'),
        MemberHelpIntent.contactWa,
      );
      expect(
        memberHelpDetectIntent('hubungi cabang'),
        MemberHelpIntent.contactWa,
      );
      expect(
        memberHelpDetectIntent('Toko lagi rame nggak?'),
        MemberHelpIntent.labQueue,
      );
      expect(
        memberHelpDetectIntent('Antrean berapa lama di Depok?'),
        MemberHelpIntent.labQueue,
      );
      expect(
        memberHelpDetectIntent('Cek stok Rayban di Depok'),
        MemberHelpIntent.stok,
      );
      expect(
        memberHelpDetectIntent('Ada stok frame progressive?'),
        MemberHelpIntent.stok,
      );
      expect(
        memberHelpDetectIntent('frame yang ready apa?'),
        MemberHelpIntent.stok,
      );
      expect(
        memberHelpDetectIntent('frame yang ready apa?'),
        isNot(MemberHelpIntent.escalateLive),
      );
      expect(
        memberHelpDetectIntent('Ada stok rak frame X?'),
        MemberHelpIntent.escalateLive,
      );
      expect(
        memberHelpDetectIntent('Antrean berapa orang?'),
        MemberHelpIntent.escalateLive,
      );
      expect(
        memberHelpDetectIntent('berapa lama pesanan saya'),
        MemberHelpIntent.orderStatus,
      );
    });
  });

  group('memberHelpFormatLabQueueReply', () {
    test('Indonesian copy distinguishes lab vs lobby', () {
      final r = memberHelpFormatLabQueueReply(
        locale: 'id',
        tokoId: 'DEPOK',
        waiting: 3,
        inProgress: 2,
        ready: 5,
        shopName: 'Optik B. Riski Depok',
      );
      expect(r, contains('Menunggu dikerjakan: 3'));
      expect(r, contains('Sedang dikerjakan: 2'));
      expect(r, contains('Siap diambil: 5'));
      expect(r.toLowerCase(), contains('bukan jumlah orang di lobby'));
      expect(r.toLowerCase(), contains('pengerjaan'));
      expect(r, isNot(contains('tidak bisa dideteksi')));
      expect(r.toLowerCase(), contains('cek stok'));
    });
  });

  group('memberHelpFormatStokReply', () {
    test('summary mode lists categories and soft disclaimer without WA push',
        () {
      final r = memberHelpFormatStokReply(
        locale: 'id',
        result: const MemberHelpStockResult(
          tokoId: 'DEPOK',
          mode: 'summary',
          skusInStock: 12,
          byKategori: [
            MemberHelpStockCategory(
              kategori: 'Frame',
              skusInStock: 10,
              totalAvailable: 40,
            ),
            MemberHelpStockCategory(
              kategori: 'Lensa',
              skusInStock: 2,
              totalAvailable: 5,
            ),
          ],
        ),
        shopName: 'Optik B. Riski Depok',
      );
      expect(r, contains('Frame'));
      expect(r, contains('10 SKU'));
      expect(r.toLowerCase(), contains('stock − reserved'));
      expect(r.toLowerCase(), contains('bukan audit rak fisik'));
      expect(r.toLowerCase(), isNot(contains('whatsapp')));
    });

    test('empty summary branch offers WhatsApp for shelf check', () {
      final r = memberHelpFormatStokReply(
        locale: 'id',
        result: const MemberHelpStockResult(
          tokoId: 'CABANG-BANYUWANGI',
          mode: 'summary',
          skusInStock: 0,
          byKategori: [],
        ),
      );
      expect(r.toLowerCase(), contains('belum ada sku'));
      expect(r.toLowerCase(), contains('whatsapp'));
    });

    test('clamps negative available qty to 0 in summary display', () {
      final r = memberHelpFormatStokReply(
        locale: 'id',
        result: const MemberHelpStockResult(
          tokoId: 'CABANG-WONOSOBO',
          mode: 'summary',
          skusInStock: 1,
          byKategori: [
            MemberHelpStockCategory(
              kategori: 'Frame',
              skusInStock: 1,
              totalAvailable: -10,
            ),
          ],
        ),
      );
      expect(r, contains('total qty ~0'));
      expect(r, isNot(contains('-10')));
      expect(memberHelpClampNonNegQty(-10), 0);
    });

    test('search mode lists SKU availability without WA push on success', () {
      final r = memberHelpFormatStokReply(
        locale: 'en',
        result: const MemberHelpStockResult(
          tokoId: 'DEPOK',
          mode: 'search',
          query: 'rayban',
          skusInStock: 12,
          matches: [
            MemberHelpStockMatch(
              sku: 'RB-1',
              nama: 'Rayban Aviator',
              kategori: 'Frame',
              warna: 'Hitam',
              availableQty: 2,
              inStock: true,
            ),
          ],
        ),
      );
      expect(r, contains('RB-1'));
      expect(r, contains('available: 2'));
      expect(r.toLowerCase(), contains('not a physical shelf'));
      expect(r.toLowerCase(), isNot(contains('whatsapp')));
    });

    test('interactive summary keeps category line and skips SKU bullets', () {
      final result = const MemberHelpStockResult(
        tokoId: 'CABANG-WONOSOBO',
        mode: 'summary',
        skusInStock: 3,
        byKategori: [
          MemberHelpStockCategory(
            kategori: 'Frame',
            skusInStock: 3,
            totalAvailable: 9,
          ),
        ],
        matches: [
          MemberHelpStockMatch(
            sku: 'F-1',
            nama: 'Frame Hitam',
            kategori: 'Frame',
            availableQty: 2,
            inStock: true,
          ),
          MemberHelpStockMatch(
            sku: 'F-2',
            nama: 'Frame Coklat',
            kategori: 'Frame',
            availableQty: 1,
            inStock: true,
          ),
        ],
      );
      final r = memberHelpFormatStokReply(
        locale: 'id',
        result: result,
        shopName: 'Wonosobo',
        interactiveProducts: true,
      );
      expect(r, contains('Frame'));
      expect(r, contains('ketuk untuk detail'));
      expect(r, isNot(contains('F-1')));
      expect(r, isNot(contains('Frame Hitam')));
    });
  });

  group('memberHelpPickStockProductsForUi', () {
    test('prefers in-stock, sorts by kategori then nama, respects max', () {
      final picked = memberHelpPickStockProductsForUi(
        const MemberHelpStockResult(
          tokoId: 'DEPOK',
          mode: 'summary',
          skusInStock: 4,
          matches: [
            MemberHelpStockMatch(
              sku: 'L-1',
              nama: 'Lensa B',
              kategori: 'Lensa',
              availableQty: 1,
              inStock: true,
            ),
            MemberHelpStockMatch(
              sku: 'F-2',
              nama: 'Frame Z',
              kategori: 'Frame',
              availableQty: 0,
              inStock: false,
            ),
            MemberHelpStockMatch(
              sku: 'F-1',
              nama: 'Frame A',
              kategori: 'Frame',
              availableQty: 3,
              inStock: true,
            ),
            MemberHelpStockMatch(
              sku: 'L-2',
              nama: 'Lensa A',
              kategori: 'Lensa',
              availableQty: 2,
              inStock: true,
            ),
          ],
        ),
        max: 2,
      );
      expect(picked.map((e) => e.sku).toList(), ['F-1', 'L-2']);
    });
  });

  group('memberHelpKeywordFallback stok', () {
    test('frame yang ready routes to stok without escalate', () {
      final r = memberHelpKeywordFallback(
        message: 'frame yang ready apa?',
        locale: 'id',
      );
      expect(r.intent, MemberHelpIntent.stok);
      expect(r.escalateWa, isFalse);
    });
  });

  group('memberHelpKeywordFallback', () {
    test('lobby people count still escalates to WA', () {
      final r = memberHelpKeywordFallback(
        message: 'Antrean berapa orang?',
        locale: 'id',
      );
      expect(r.escalateWa, isTrue);
      expect(r.intent, MemberHelpIntent.escalateLive);
      expect(r.reply.toLowerCase(), contains('lobby'));
      expect(r.suggestedChips, contains(MemberHelpChipId.contactWa));
      expect(r.suggestedChips, contains(MemberHelpChipId.labQueue));
      expect(r.suggestedChips, contains(MemberHelpChipId.stok));
    });

    test('lab queue keyword suggests lab chip (not invent lobby minutes)', () {
      final r = memberHelpKeywordFallback(
        message: 'Antrean lab berapa?',
        locale: 'id',
      );
      expect(r.escalateWa, isFalse);
      expect(r.intent, MemberHelpIntent.labQueue);
      expect(r.reply.toLowerCase(), contains('pengerjaan'));
      expect(r.suggestedChips, contains(MemberHelpChipId.labQueue));
    });

    test('system stok keyword suggests stok chip', () {
      final r = memberHelpKeywordFallback(
        message: 'Cek stok frame',
        locale: 'id',
      );
      expect(r.escalateWa, isFalse);
      expect(r.intent, MemberHelpIntent.stok);
      expect(r.reply.toLowerCase(), contains('stok'));
      expect(r.suggestedChips, contains(MemberHelpChipId.stok));
    });

    test('WA contact free-text escalates without phone dump', () {
      final r = memberHelpKeywordFallback(
        message: 'bagi nomor wa dong',
        locale: 'id',
      );
      expect(r.escalateWa, isTrue);
      expect(r.intent, MemberHelpIntent.contactWa);
      expect(r.reply.toLowerCase(), contains('whatsapp'));
      // Client owns XOR — fallback must not promise GPS + ask-location together.
      expect(r.reply.toLowerCase(), isNot(contains('lokasi tidak')));
      expect(r.reply, isNot(contains(RegExp(r'\d{8,}'))));
    });

    test('unknown without gemini suggests chips + WA', () {
      final r = memberHelpKeywordFallback(
        message: 'xyzabc random',
        locale: 'id',
      );
      expect(r.escalateWa, isTrue);
      expect(r.suggestedChips, isNotEmpty);
      expect(r.suggestedChips, contains(MemberHelpChipId.labQueue));
      expect(r.suggestedChips, contains(MemberHelpChipId.stok));
      expect(r.reply.toLowerCase(), contains('tidak tersedia'));
      expect(r.reply.toLowerCase(), isNot(contains('belum dikonfigurasi')));
    });
  });

  group('MemberHelpBotReply.isSoftGeminiFailure', () {
    test('flags rate-limit / unavailable codes only', () {
      expect(
        const MemberHelpBotReply(
          reply: 'x',
          errorCode: 'gemini_rate_limited',
        ).isSoftGeminiFailure,
        isTrue,
      );
      expect(
        const MemberHelpBotReply(
          reply: 'x',
          errorCode: 'gemini_unavailable',
        ).isSoftGeminiFailure,
        isTrue,
      );
      expect(
        const MemberHelpBotReply(reply: 'Halo').isSoftGeminiFailure,
        isFalse,
      );
      expect(
        const MemberHelpBotReply(
          reply: 'x',
          errorCode: 'gemini_unconfigured',
        ).isSoftGeminiFailure,
        isFalse,
      );
    });
  });
}
