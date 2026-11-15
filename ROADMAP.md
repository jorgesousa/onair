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
- [ ] Mac: pôr também o cartão do canal em baixo à esquerda no modo Watch (o canto de cima é do resultado)
- [ ] Juntar o ramo `ipad` ao `main` (precisa de OK)

## Next
- [x] TV como segundo ecrã (janela em ecrã inteiro no ecrã da TV), como peça isolada sem mexer na reprodução — esboço em `airplay-experiments:Sources/OnAir/TVScreen.swift`
- [ ] AirPlay: só o botão normal do leitor; canais do fornecedor com limite de 1 ligação não são fiáveis por AirPlay directo

- [ ] Partilhar a ligação única entre Mac e iPad. Primeiro (pequeno): passar a sessão já resolvida do Mac para o iPad ("Ver no iPad") e guardar a sessão para um reinício não esperar ~2 min — medir com `connections()`. Depois, se valer a pena: relay dentro da app do Mac (Bonjour, mesmo canal em vários aparelhos) ou Dispatcharr num aparelho sempre ligado. Uma ligação = um canal de cada vez.

- [ ] Dispatcharr em casa: correr o Dispatcharr (Docker, num aparelho sempre ligado) com a conta do fornecedor, apontar o ONAIR do Mac e do iPad para a API Xtream dele, e confirmar que dois aparelhos no mesmo canal gastam uma só ligação (`active_cons`). Ver se o caminho `.m3u8` funciona tal como está.

## Later
- Transição do sintonizador (barras + número) no ecrã da TV
- Versão Android (tablet): app à parte em Kotlin + Jetpack Compose com Media3/ExoPlayer, a portar o núcleo (modelos, M3U, Xtream, guia, ~640 linhas) e a refazer a interface; alternativa a avaliar: Skip (SwiftUI → Compose). Antes disso, manter o núcleo da versão iPad sem dependências de interface para a passagem ser mais fácil
- ~~Motor de vídeo mais tolerante (mpv)~~ — avaliado a 2026-11-14, não justifica (perde AirPlay/PiP, licença GPL, +40–60 MB)
