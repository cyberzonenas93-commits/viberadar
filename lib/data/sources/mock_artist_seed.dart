import '../../models/artist.dart';

List<Artist> buildMockArtists() => const [
      Artist(
        id: 'burna-boy',
        name: 'Burna Boy',
        imageUrl:
            'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?auto=format&fit=crop&w=400&q=80',
        genres: ['Afrobeats'],
        country: 'NG',
        bio:
            'Grammy-winning Nigerian singer and songwriter blending Afrobeats, dancehall, and R&B into a global sound.',
        trendScore: 0.96,
        monthlyListeners: 45200000,
        verified: true,
        topTrackIds: ['bb-01', 'bb-02', 'bb-03', 'bb-04', 'bb-05'],
      ),
      Artist(
        id: 'wizkid',
        name: 'Wizkid',
        imageUrl:
            'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?auto=format&fit=crop&w=400&q=80',
        genres: ['Afrobeats'],
        country: 'NG',
        bio:
            'Lagos-born Afrobeats icon known for infectious rhythms and collaborations with global superstars.',
        trendScore: 0.91,
        monthlyListeners: 38700000,
        verified: true,
        topTrackIds: ['wk-01', 'wk-02', 'wk-03', 'wk-04', 'wk-05'],
      ),
      Artist(
        id: 'tems',
        name: 'Tems',
        imageUrl:
            'https://images.unsplash.com/photo-1534294668821-28a3054f4256?auto=format&fit=crop&w=400&q=80',
        genres: ['Afrobeats', 'R&B'],
        country: 'NG',
        bio:
            'Afro-soul singer-songwriter whose velvety voice bridges Nigerian Afrobeats with contemporary R&B.',
        trendScore: 0.88,
        monthlyListeners: 32100000,
        verified: true,
        topTrackIds: ['tm-01', 'tm-02', 'tm-03', 'tm-04', 'tm-05'],
      ),
      Artist(
        id: 'rema',
        name: 'Rema',
        imageUrl:
            'https://images.unsplash.com/photo-1571266028243-d220c6a8ade5?auto=format&fit=crop&w=400&q=80',
        genres: ['Afrobeats'],
        country: 'NG',
        bio:
            'Benin City-born trailblazer fusing Afrobeats, trap, and emo into a distinctive Afrorave movement.',
        trendScore: 0.94,
        monthlyListeners: 28900000,
        verified: true,
        topTrackIds: ['rm-01', 'rm-02', 'rm-03', 'rm-04', 'rm-05'],
      ),
      Artist(
        id: 'davido',
        name: 'Davido',
        imageUrl:
            'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?auto=format&fit=crop&w=400&q=80',
        genres: ['Afrobeats'],
        country: 'NG',
        bio:
            'Afrobeats heavyweight and founder of DMW label, known for anthems that dominate dance floors globally.',
        trendScore: 0.82,
        monthlyListeners: 27400000,
        verified: true,
        topTrackIds: ['dv-01', 'dv-02', 'dv-03', 'dv-04', 'dv-05'],
      ),
      Artist(
        id: 'kabza-de-small',
        name: 'Kabza De Small',
        imageUrl:
            'https://images.unsplash.com/photo-1598488035139-bdbb2231ce04?auto=format&fit=crop&w=400&q=80',
        genres: ['Amapiano'],
        country: 'ZA',
        bio:
            'The King of Amapiano, Kabza De Small is the architect of South Africa\'s biggest music export.',
        trendScore: 0.87,
        monthlyListeners: 19200000,
        verified: true,
        topTrackIds: ['kds-01', 'kds-02', 'kds-03', 'kds-04', 'kds-05'],
      ),
      Artist(
        id: 'dj-maphorisa',
        name: 'DJ Maphorisa',
        imageUrl:
            'https://images.unsplash.com/photo-1618609377864-68609b857e90?auto=format&fit=crop&w=400&q=80',
        genres: ['Amapiano'],
        country: 'ZA',
        bio:
            'Veteran producer and DJ who helped define the Amapiano sound and mentor the next generation.',
        trendScore: 0.83,
        monthlyListeners: 17800000,
        verified: true,
        topTrackIds: ['dm-01', 'dm-02', 'dm-03', 'dm-04', 'dm-05'],
      ),
      Artist(
        id: 'uncle-waffles',
        name: 'Uncle Waffles',
        imageUrl:
            'https://images.unsplash.com/photo-1504680177321-2e6a879aac86?auto=format&fit=crop&w=400&q=80',
        genres: ['Amapiano'],
        country: 'ZA',
        bio:
            'Zimbabwean-born DJ and dancer whose electric stage presence brought Amapiano to the world stage.',
        trendScore: 0.79,
        monthlyListeners: 14500000,
        verified: true,
        topTrackIds: ['uw-01', 'uw-02', 'uw-03', 'uw-04', 'uw-05'],
      ),
      Artist(
        id: 'sza',
        name: 'SZA',
        imageUrl:
            'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?auto=format&fit=crop&w=400&q=80',
        genres: ['R&B'],
        country: 'US',
        bio:
            'TDE\'s genre-defining voice whose introspective lyricism and alt-R&B sound reshaped modern soul.',
        trendScore: 0.93,
        monthlyListeners: 41300000,
        verified: true,
        topTrackIds: ['sz-01', 'sz-02', 'sz-03', 'sz-04', 'sz-05'],
      ),
      Artist(
        id: 'drake',
        name: 'Drake',
        imageUrl:
            'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&w=400&q=80',
        genres: ['Hip-Hop'],
        country: 'CA',
        bio:
            'Toronto rapper and OVO founder whose melodic rap style dominates streaming charts worldwide.',
        trendScore: 0.89,
        monthlyListeners: 68900000,
        verified: true,
        topTrackIds: ['dk-01', 'dk-02', 'dk-03', 'dk-04', 'dk-05'],
      ),
      Artist(
        id: 'travis-scott',
        name: 'Travis Scott',
        imageUrl:
            'https://images.unsplash.com/photo-1541701494587-cb58502866ab?auto=format&fit=crop&w=400&q=80',
        genres: ['Hip-Hop'],
        country: 'US',
        bio:
            'Houston\'s Cactus Jack creates psychedelic trap soundscapes that blur the line between rap and rock.',
        trendScore: 0.86,
        monthlyListeners: 44100000,
        verified: true,
        topTrackIds: ['ts-01', 'ts-02', 'ts-03', 'ts-04', 'ts-05'],
      ),
      Artist(
        id: 'fred-again',
        name: 'Fred Again',
        imageUrl:
            'https://images.unsplash.com/photo-1571266028243-e4c20ac8fb8b?auto=format&fit=crop&w=400&q=80',
        genres: ['House', 'Electronic'],
        country: 'GB',
        bio:
            'London producer and Brian Eno protégé crafting emotionally charged house music from real-life moments.',
        trendScore: 0.95,
        monthlyListeners: 22600000,
        verified: true,
        topTrackIds: ['fa-01', 'fa-02', 'fa-03', 'fa-04', 'fa-05'],
      ),
      Artist(
        id: 'kendrick-lamar',
        name: 'Kendrick Lamar',
        imageUrl:
            'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?auto=format&fit=crop&w=400&q=80',
        genres: ['Hip-Hop'],
        country: 'US',
        bio:
            'Pulitzer Prize-winning Compton rapper and pgLang founder — one of the most acclaimed artists of his generation.',
        trendScore: 0.97,
        monthlyListeners: 52100000,
        verified: true,
        topTrackIds: ['kl-01', 'kl-02', 'kl-03', 'kl-04', 'kl-05'],
      ),
      Artist(
        id: 'black-coffee',
        name: 'Black Coffee',
        imageUrl:
            'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?auto=format&fit=crop&w=400&q=80',
        genres: ['House', 'Afro House'],
        country: 'ZA',
        bio:
            'Grammy-winning South African DJ and producer whose Afro House sound fills the world\'s finest clubs.',
        trendScore: 0.85,
        monthlyListeners: 18400000,
        verified: true,
        topTrackIds: ['bc-01', 'bc-02', 'bc-03', 'bc-04', 'bc-05'],
      ),
    ];
