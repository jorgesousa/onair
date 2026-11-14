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
- [ ] Publicar 0.1.4 com a regra de uma ligação (precisa de OK)

## Next
- [x] TV como segundo ecrã (janela em ecrã inteiro no ecrã da TV), como peça isolada sem mexer na reprodução — esboço em `airplay-experiments:Sources/OnAir/TVScreen.swift`
- [ ] AirPlay: só o botão normal do leitor; canais do fornecedor com limite de 1 ligação não são fiáveis por AirPlay directo

## Later
- Transição do sintonizador (barras + número) no ecrã da TV
- Motor de vídeo mais tolerante (tipo VLC/mpv) para canais cujo vídeo o descodificador do Mac rejeita
