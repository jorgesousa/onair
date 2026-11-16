# Roadmap — onair

## Now
- [x] Simplificar: voltar à base 0.1.3 + uma ligação de cada vez ao fornecedor (main = 82903de)
- [x] Retransmissor, canal virtual e AirPlay experimental guardados no ramo `airplay-experiments`
- [x] Reprodução no Mac testada: RTP 1/1 HD, RTP África, SIC Radical com imagem; RTP Memória só com som (do canal)
- [x] Aviso SOUND ONLY quando um canal toca sem imagem
- [x] Sem espera cega de 2 min quando a API do fornecedor não responde (auth 0)
- [x] Imagem preta com som (2026-11-14): o descodificador de vídeo do Mac rejeita os dados de vídeo de alguns canais (VideoToolbox -8969, ~25/s), em todas as versões; não vem das alterações da app
- [x] Revertido o "observador de imagem" (AVPlayerItemVideoOutput) da deteção SOUND ONLY
- [ ] Testar o modo TV com a Samsung como ecrã separado
- [x] Modo Watch: ecrã inteiro esconde a lista e a now bar; cartão do canal no canto superior esquerdo (aparece logo ao fazer zap, com o rato desvanece); lista espreita pela borda esquerda; esc volta
- [x] A now bar nunca encolhe a imagem: em janelas largas e baixas flutua por cima e esconde-se
- [x] Movimento: cartão de teste a desligar (02), passagem para a TV e TV a ligar/desligar a partir de uma linha (03), próximo programa e linha NEXT na now bar (04), primeira carga em cascata (05), destaque sem deslizar nas teclas
- [x] Teclas: números para ir ao canal, ⌫ volta ao canal anterior; o que dá agora/a seguir ao passar o rato (dica)
- [x] Lista compacta (só número + nome), no menu da lista
- [x] Ecrã ONAIR durante Picture in Picture (em vez do cinzento da Apple)
- [x] Revisto numa cópia de teste (fornecedor falso, streams de teste): cartão de teste a dobrar, ↑↓, números, ⌫, guia/NEXT/troca de programa, barra flutuante, lista compacta, modo Watch, esc, PiP
- [x] Auditoria das duas revisões (minha + agente independente): corrigidos 05 só ao adicionar/mudar de playlist, linhas de progresso paradas, Watch 0,22 s, cartão 0,2 s, número a contar, dígitos no cartão, imagem a ir para a TV e voltar, NEXT ao passar o rato, cartão da TV 3 s, cartão de teste a aparecer em fade, Reduce Motion com fades, hover instantâneo, linhas compactas 34 pt, ⏎ em toda a janela, fades por cima da imagem
- [ ] Por testar: lista a espreitar pela borda esquerda e NEXT ao passar o rato (precisam do rato), modo TV com a Samsung
- [ ] Publicar 0.1.4 com a regra de uma ligação (precisa de OK)
- [x] iPad (ramo `ipad`): código partilhado em `Sources/OnAirCore`, app iPad em `iPad/OnAir.xcodeproj` + `Sources/OnAirPad`; o Mac continua igual
- [x] iPad: lista, modo Watch em paisagem, imagem por cima e lista por baixo em retrato, lista a espreitar pela borda, deslizar para cima/baixo muda de canal (cartão em baixo à esquerda, longe do resultado), voltar ao último canal, controlos grandes, AirPlay, PiP sem botões de saltar
- [x] iPad: ecrã sempre aceso a ver; a ligação ao fornecedor é libertada se ninguém vê a imagem (sair sem PiP, fechar o PiP, PiP em pausa 10 s) e fica "Resume" a um toque
- [x] iPad: 23 testes de interface no simulador (iPad Pro 13, iPad mini em iOS 26.5, iPad Air 11) contra o fornecedor falso (`scripts/fake-provider.py`, `scripts/test-ipad.sh`) + revisão independente com correções
- [ ] iPad no aparelho real (precisa do Jorge): ligar por cabo, Developer Mode, instalar pelo Xcode; confirmar ecrã aceso durante um jogo, PiP por cima de outra app, teclado físico, ficheiro M3U pela app Ficheiros, janelas do iPadOS 26
- [ ] iPad: pequenos pendentes da revisão — zap pendente não cancelado por toque na lista, uma só janela, ⏎ em paisagem, menu da playlist nos controlos, apagar cópias de ficheiros ao remover
- [x] iPad: now bar ao mudar de canal — a barra fica parada, o título sobe por baixo e o resto troca com fade e desfoque leve (0,26 s); também no Mac
- [ ] iPad: confirmar no iPad do Jorge a lista nova (sem linhas a ficar vazias ao fazer scroll rápido) e a troca de texto na now bar
- [x] Ligação recusada pelo fornecedor: a app deixa de insistir sozinha durante 2 min (contagem decrescente no aviso; se o fornecedor disser que já há vaga, tenta mais cedo); escolher um canal à mão tenta logo, uma vez. Testado com um servidor que recusa tudo (`RefusalTests`)
- [x] Canal com vídeo que o aparelho não descodifica (-12863): pára e diz "This iPad can't play this channel's video" em vez de tentar para sempre
- [ ] Confirmar no iPad a espera de 2 min com o fornecedor real e o aviso dos canais que o iPad não lê
- [x] iPhone (ramo `ipad`): a mesma app, agora universal — lista, imagem em cima e now bar estreita em retrato, modo Watch em paisagem com zap por deslizar, cartão do canal mais pequeno, folha de playlist a 1×. Visto no simulador (iPhone 17 Pro). Desenho em `docs/superpowers/specs/2026-11-15-iphone-design.md`
- [x] iPhone: o botão de ecrã inteiro em retrato roda para paisagem (como a app TV) e fica assim até o telefone estar deitado; depois o telefone manda e pô-lo de pé volta ao retrato. Em paisagem o botão volta ao retrato. Controlos afastados da ilha dinâmica. O iPad não roda
- [ ] iPhone no aparelho real: instalado no "iPhone JS" (Release, com Movies, Personal, Free TV e Home); falta testar e testar PiP por cima de outras apps, rede móvel, ilha dinâmica, o botão de sair do ecrã inteiro em paisagem (no simulador os toques em paisagem chegam trocados)
- [x] Paisagem (iPad e iPhone): escolher um canal na lista lateral já não mexe tudo ao mesmo tempo — a linha acende logo, 0,12 s depois a lista sai num só movimento enquanto a imagem abre já com o cartão de teste, e o cartão do canal só aparece depois. A ligação começa no toque. Retrato fica igual. Visto em vídeo no simulador do iPad
- [ ] Confirmar no iPad (e no iPhone em paisagem) a escolha de canal na lista lateral
- [x] "Off air": um canal que nunca mostra nada ao fim de 3 tentativas e 20 s diz "Off air · this channel isn't broadcasting right now" em vez de ficar em "Reconnecting"; um toque tenta de novo (Personal e Home). Testado com um servidor que responde 404. Ecrã próprio no estilo do resto: o cartão de teste a cinzento com o cartão de papel "OFF AIR · <canal>"
- [x] Home: o "ocupado" do Dispatcharr (503/500, ainda a largar o canal anterior) já não passa por "off air": tenta a cada 2 s com o cartão "Tuning in" à vista (sem aviso por cima) e só desiste aos 45 s. No Personal fica a espera normal (cada tentativa podia contar como ligação)
- [x] Correção automática: inspeciona no máximo 2,5 s (antes 2 MB, que num canal SD eram ~10 s e o Dispatcharr desistia aos 5 s — TVI LOW)
- [x] O cartão "Tuning in" já não pisca para preto entre tentativas (nem no arranque): sem stream carregado e com canal escolhido, continua a sintonizar. Teste `tuningStaysOnBetweenAttempts`; visto no Mac com RTP Internacional (cartão fixo → ecrã "Off air" aos ~45 s)
- [x] Mudar de canal no Home mais rápido: o Dispatcharr larga o canal anterior ao fim de 6 s (era 12) e o ONAIR pede a sessão HLS ao Dispatcharr ele próprio, um pedido de cada vez (a cada 2 s enquanto "ocupado"), e entrega ao leitor a playlist já resolvida — acabaram os clientes "fantasma" e os arranques em duplicado. Juntar-se a um canal já a dar: ~0,2 s + imagem no primeiro segundo
- [x] Guia (EPG) no Home: o ONAIR lê o endereço do guia do cabeçalho da playlist (`url-tvg`/`x-tvg-url`) quando não há conta Xtream; no Dispatcharr, fonte "Provider guide" (XMLTV do fornecedor, 646 canais) e 210 dos 268 canais ligados ao guia pelo código exacto do fornecedor (`tvg-id`). Os 58 sem código ficam sem guia (a correspondência por nome do Dispatcharr errava, ex.: SIC Novelas → SIC Notícias). Visto no Mac
- [ ] Guia: os canais novos que o fornecedor acrescentar precisam de ser ligados pelo código (repetir a ligação depois de cada actualização da lista, ou um pequeno script nocturno)
- [x] Mac: a linha NEXT ao passar o rato numa linha da lista usa o mesmo tipo de letra da linha que substitui (antes trocava para monoespaçado e mais pequeno) e, se não couber, desliza como os títulos da barra em vez de cortar com "…"
- [x] Revisão de consistência (2026-11-15, página "ONAIR Consistency Review"): A1 "Sound only" diz o aparelho; A3 "Can't play" passa a cartão como o Off air (componente comum `EndCard`); A4 no Mac o cartão aparece no palco e na TV, uma só redacção; B6 botões Primary/Secondary/LinkPill partilhados pelos três aparelhos (44 pt no toque) e botões em maiúsculas; B7 linha NEXT igual em todo o lado ("NEXT 22:00" mono + " · título"); B8 etiqueta do menu de playlist partilhada ("HOME ⌄", o chevron já não salta para a esquerda no Mac); B9 About no iPad/iPhone com "Report a problem" e os botões do Mac
- [ ] Revisão: A2 (aviso no mesmo sítio em todos os aparelhos) e A5 (reticências) por fazer; Pacote C (alvos de toque, Reduce Motion, cartões no iPhone, tokens de movimento) por fazer
- [ ] Ver no ecrã: cartão CAN'T PLAY, cartão na TV, About do iPad a quebrar em duas linhas
- [ ] Mac: pôr também o cartão do canal em baixo à esquerda no modo Watch (o canto de cima é do resultado)
- [ ] iPad: rever as categorias (o filtro Category está escondido no iPad por agora — `PadRail.showsCategories`)
- [ ] Juntar o ramo `ipad` ao `main` (precisa de OK)
- [x] Vídeo novo (v6, 23 s) para Mac, iPad e iPhone: cena nova com os três aparelhos a entrar no tempo e a sintonizar o mesmo canal; `docs/onair.mp4`, `docs/onair-poster.jpg`, `docs/onair.gif` (GIF no topo do README). Ferramentas em `brag-output-2026-11-16-171848/work` (ignorado pelo Git)
- [x] README: iPad e iPhone, "One TV, several screens" (Dispatcharr), instalar no iOS pelo Xcode, OFF AIR / CAN'T PLAY
- [ ] Publicar README e vídeo (vão com o ramo `ipad`; precisa de OK)

## Next
- [x] TV como segundo ecrã (janela em ecrã inteiro no ecrã da TV), como peça isolada sem mexer na reprodução — esboço em `airplay-experiments:Sources/OnAir/TVScreen.swift`
- [ ] AirPlay: só o botão normal do leitor; canais do fornecedor com limite de 1 ligação não são fiáveis por AirPlay directo

- [ ] Partilhar a ligação única entre Mac e iPad. Primeiro (pequeno): passar a sessão já resolvida do Mac para o iPad ("Ver no iPad") e guardar a sessão para um reinício não esperar ~2 min — medir com `connections()`. Depois, se valer a pena: relay dentro da app do Mac (Bonjour, mesmo canal em vários aparelhos) ou Dispatcharr num aparelho sempre ligado. Uma ligação = um canal de cada vez.

- [ ] Dispatcharr em casa: correr o Dispatcharr (Docker, num aparelho sempre ligado) com a conta do fornecedor, apontar o ONAIR do Mac e do iPad para a API Xtream dele, e confirmar que dois aparelhos no mesmo canal gastam uma só ligação (`active_cons`). Ver se o caminho `.m3u8` funciona tal como está.
  - [x] Teste rápido no Mac (2026-11-15): Dispatcharr 0.33 em Docker via Colima (binários oficiais em `~/.local/colima-test`, o Homebrew Intel deste Mac não compila o Lima; arrancar com `PATH=~/.local/colima-test/bin:~/.local/colima-test/lima/bin:$PATH colima start`). Conta M3U "Provider" com Max Streams 1, grupo Portugal → 268 canais. Dois clientes no mesmo canal (RTP 1 HD) = **1 ligação no fornecedor** (active 1 de 1). AVPlayer toca o HLS do Dispatcharr (`<canal>?output_format=hls`, 1280×720), mas demora ~15 s a arrancar
  - [x] Playlist **Home** no ONAIR: no Mac `http://127.0.0.1:9191/output/m3u?output_format=hls`; no iPhone `http://192.168.1.67:9191/…` (Dispatcharr agora aberto na rede de casa, porta 9191). Sem guia ainda (o Dispatcharr não tem EPG configurado)
  - [x] Teste real (2026-11-15): iPhone e Mac no mesmo canal pelo Home ao mesmo tempo, fornecedor a contar **1 de 1**. Houve um corte curto no início: o Dispatcharr marcou clientes HLS como "ghost" e desligou-os (cada AVPlayer abre vários pedidos ao arrancar); depois estabilizou
  - [x] **Uma TV, vários ecrãs** (2026-11-15): no Home, mudar de canal num ecrã muda em todos (Bonjour `_onair._tcp`, `HomeLink` + `Follow` + `.followsHome` em `OnAirCore`); quem abre o Home junta-se ao que está a dar; as outras playlists ficam independentes. Testado entre Mac e iPhone: segue nos dois sentidos
  - [x] Canais do Dispatcharr têm 40 s para a primeira imagem (antes 15 s → ciclo de "Reconnecting" porque o HLS demora ~15 s)
  - [x] Dispatcharr afinado (cópia de `config.py` em `~/.local/colima-test/dispatcharr/`, montada por cima): `CLIENT_RECORD_TTL` 60→12 s (o canal anterior larga a ligação mais depressa) e `HLS_SEGMENT_DURATION` 4→2 s
  - [ ] Mudar de canal ainda é lento e às vezes um ecrã arranca antes do outro: o Dispatcharr recusa o canal novo (503, "max connections") enquanto o anterior não larga; o ONAIR tenta de novo com esperas que crescem (1, 1, 3, 8 s…). Para o Home: tentar a cada 2 s durante ~30 s quando o Dispatcharr diz "ocupado", e mostrar "a mudar de canal" em vez de "Reconnecting"
  - [ ] Os vários pedidos com que o AVPlayer arranca aparecem no Dispatcharr como clientes "ghost" e são desligados — ver se vale a pena pedir logo o `index.m3u8`
  - [x] Canais só com som (RTP Memória, RTP 1 Full HD): o fornecedor manda H.264 com 5 frames de referência onde o nível só deixa 4; o descodificador da Apple (Mac e iPhone) recusa a imagem, o ffmpeg ignora. No Home resolve-se no Dispatcharr com o perfil **Fix video (x264)** (ffmpeg → libx264 veryfast 720p, áudio copiado; ~50% de um núcleo) aplicado só a esses canais. Testado: RTP Memória com imagem no Mac e no iPhone
  - [x] RTP 1 HD dava no Mac mas não no iPhone: o áudio é MP2, que o iPhone não aceita dentro de HLS. Perfil **Fix audio (AAC)** no Dispatcharr (vídeo copiado, áudio → AAC, ~6% de CPU). O "Fix video" também converte o áudio para AAC. Testado: RTP 1 HD no iPhone com imagem e som
  - [x] Varrimento dos 268 canais do grupo Portugal (2026-11-15): 111 dão como estão, 9 só precisam do áudio (MP2), 65 do vídeo, 41 dos dois, 42 sem emissão nesse momento. Quase todos os Full HD são 1080i com o defeito dos frames de referência; as versões HD dos desportos (Sport TV 1/4/5/6, Benfica TV, Da Zone 1/2/3/5) dão tal como estão. Resultados em `~/.local/colima-test/dispatcharr/scan-*.jsonl` (`scan.py`)
  - [x] **Correção automática** (`onair-fix.sh`, perfil "ONAIR auto-fix", agora o perfil por omissão do Dispatcharr): lê o canal numa só ligação, inspeciona os primeiros ~2 MB e decide — deixa passar, converte só o áudio para AAC, ou recodifica o vídeo para 720p H.264 (com desentrelaçamento). Testado em SIC HD (passa), SIC (áudio) e Sport TV 1 Full HD (vídeo), todos em tempo real
  - [ ] Desporto a 50 imagens/s depois de desentrelaçar (`yadif=mode=1`) e a VM do Colima com 4 núcleos em vez de 2
  - [ ] Varrimento nocturno + etiqueta "OFF AIR" na lista do Home (só indicação; o ONAIR tenta sempre)
  - [ ] Para o Personal (sem Dispatcharr): leitor de recurso tolerante (VLCKit ou mpv) só para canais que a Apple recusa — decisão grande (peso, licenças)
  - [ ] Afinar o arranque HLS (~15 s); pôr o Home também no iPad; dar ao Dispatcharr o guia (EPG) do fornecedor; o IP do Mac pode mudar (reservar no router)
  - [ ] Decidir onde fica a correr sempre (Mac ligado, mini PC ou NAS)

## Later
- [x] iPhone: app própria a partir do `OnAirCore` (feito como app universal, ver Now) (retrato = imagem em cima e lista por baixo; paisagem = ecrã inteiro com zap por deslizar). Ver desafios: ecrã pequeno, ilha dinâmica/zonas seguras, sem janelas, PiP como forma principal de "ver enquanto faço outra coisa", rede móvel e a ligação única
- Transição do sintonizador (barras + número) no ecrã da TV
- Versão Android (tablet): app à parte em Kotlin + Jetpack Compose com Media3/ExoPlayer, a portar o núcleo (modelos, M3U, Xtream, guia, ~640 linhas) e a refazer a interface; alternativa a avaliar: Skip (SwiftUI → Compose). Antes disso, manter o núcleo da versão iPad sem dependências de interface para a passagem ser mais fácil
- ~~Motor de vídeo mais tolerante (mpv)~~ — avaliado a 2026-11-14, não justifica (perde AirPlay/PiP, licença GPL, +40–60 MB)
