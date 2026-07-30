# Instruktion till Codex

Använd följande text när projektet lämnas över till en ny Codex-session:

> Läs först `AGENTS.md`, `README.md`, `DEVELOPMENT.md` och `CHANGELOG.md`.
> Behandla dokumenterade CLI-kommandon, versionsregler, SHA-256-kontroller,
> externa verktygsargument och formatet för `skit.yml` som
> bakåtkompatibilitetskontrakt.
>
> Implementera den efterfrågade ändringen i
> `SCUM-Mod-Toolkit.ps1`. Behåll kompatibilitet med Windows PowerShell 5.1
> och gör inga installationer eller PATH-ändringar när scriptet dot-sourcas.
> Kod, funktionsnamn, kommentarer, loggtexter, felmeddelanden och testnamn ska
> vara på engelska. Användardokumentation ska vara på svenska.
>
> Lägg till eller uppdatera Pester-tester för både normalfall och relevanta
> fel. Kör hela testsviten i Windows PowerShell 5.1. Uppdatera dokumentation
> och `CHANGELOG.md` när beteendet ändras. Om detta är en ny version av SKit,
> uppdatera även `$script:SKitVersion`.
>
> Verifiera ändringar av repak, UAssetGUI, FModel eller GitHub API mot
> respektive officiella upstream-källa. Försvaga inte SHA-256-verifieringen.
>
> Avsluta med en kort sammanställning av ändrade filer, testresultat och
> sådant som fortfarande kräver ett riktigt Windows/SCUM-test.

Lägg till den konkreta uppgiften efter texten, exempelvis:

> Uppgift: Lägg till kommandot `skit clean`, som tar bort projektets lokala
> buildartefakter efter tydlig bekräftelse.
