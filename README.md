# VozFlow

Ditado por voz para qualquer app do macOS, direto da barra de menus. Projeto original, escrito do zero.

## Como usar

| Ação | Como |
|---|---|
| Ditar (push-to-talk) | Segure **⌥ Option direito**, fale, solte. O texto é colado onde o cursor está. |
| Mãos livres | Toque rápido na tecla; toque de novo para terminar. |
| Cancelar | **Esc** durante a gravação. |
| Comandos de voz | "nova linha", "novo parágrafo". |
| Enviar mensagem | Termine com "envia agora" (configurável): cola e pressiona Enter. |
| Editar por voz | Selecione um texto, segure a tecla e diga a alteração ("deixa mais formal", "traduz pro inglês"). Requer IA. |
| Colar a última transcrição | **⌃⌥V** ou menu. |

A tecla pode ser trocada em **Preferências › Geral** (Option, Command ou Control direitos, ou fn).

## Recursos

- Reconhecimento de fala da Apple, de preferência no próprio Mac (offline): pt-BR, pt-PT, en, es, fr, it, de.
- Texto parcial aparece ao vivo no indicador enquanto você fala.
- Escolha do microfone, conjuntos de sons, opção de silenciar o som do Mac durante o ditado e aviso quando o microfone parece mudo.
- **Refinamento com IA** (opcional), com **Claude** (Anthropic) ou **Gemini** (Google): remove vícios de fala, corrige pontuação, aplica autocorreções ("às duas, não, às três" → "às três") e ajusta o tom ao app em foco. Só o texto vai para a API, nunca o áudio. As chaves ficam no Keychain.
  - Gemini: modelos Flash-Lite (padrão, mais rápido), Flash e Pro (este só com plano pago). Se o modelo estiver sobrecarregado, o app tenta de novo com o Flash-Lite. No plano gratuito, o Google pode usar o texto enviado para melhorar os produtos dele.
  - Instruções personalizadas de estilo.
  - Tradução do ditado para outro idioma.
  - Contexto do campo (opcional): usa o texto já digitado para acertar nomes e tom.
  - Modo edição por voz sobre o texto selecionado.
- Dicionário: vocabulário, substituições `errado => certo` e snippets com `\n`.
- Estatísticas: palavras, palavras por minuto, tempo economizado e dias seguidos.
- Histórico dos últimos 30 ditados (menu e preferências).
- Restaura a área de transferência depois de colar, sem poluir gerenciadores de clipboard.
- Abrir ao iniciar sessão.

## Permissões (primeira execução)

1. **Microfone** e **Reconhecimento de fala**: aceite os pedidos do sistema.
2. **Acessibilidade**: Ajustes do Sistema › Privacidade e Segurança › Acessibilidade › ative o VozFlow. É necessária para o atalho global e para colar o texto.

Se o reconhecimento falhar com o modo offline ligado, ative **Ajustes do Sistema › Teclado › Ditado**; enquanto isso o VozFlow usa o servidor da Apple automaticamente. Para investigar problemas de reconhecimento:

```bash
open -n -W VozFlow.app --args --diagnose && cat ~/Library/Logs/VozFlow-diagnostico.txt
```

## Compilar

Requisitos: macOS 14 ou superior e as Command Line Tools do Xcode (`xcode-select --install`).

```bash
bash Tools/setup_signing.sh   # opcional, uma vez: assinatura local fixa
bash build.sh
```

Gera `../VozFlow.app` (universal: Apple Silicon + Intel).

- Com `setup_signing.sh`, o app é assinado com um certificado local fixo, e as permissões continuam valendo entre builds.
- Sem ele, a assinatura é ad-hoc: a cada build o macOS trata o app como novo, e é preciso remover e adicionar o VozFlow de novo em Acessibilidade.

Para desfazer a assinatura local: `security delete-keychain ~/Library/Keychains/vozflow-signing.keychain-db`.

## Licença

[MIT](LICENSE)
