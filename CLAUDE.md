# Solvenin ERP — Claude Code Kuralları

Bu projede iş yaparken:

## 1. Her komut bir iştir
- Komut "bug X'i düzelt" derse SADECE X'i düzelt
- Yol üzerinde "bu arada şunu da iyileştireyim" YAPMA
- Refactor komutla gelmedikçe refactor yapma
- Başka dosyaları "temizleme", "modernize etme", "tutarlı hale getirme"

## 2. Regression bulmacası
Bir davranışı değiştirmeden önce o davranışın BAŞKA NEREDE kullanıldığını kontrol et:
- Aynı componentin edit modu var mı?
- Aynı modal başka sayfadan da açılıyor mu?
- Aynı fonksiyon başka yerde çağrılıyor mu?
- DB kolonunu kullanan başka sayfa var mı?

En az 1 grep yap, sonra değiştir.

## 3. Legacy koru
- Eski kayıtlar farklı field değerleri kullanıyor olabilir (category='expense' gibi)
- Yeni sistem eskilerle uyumlu kalmalı
- Veri migration sadece komutta AÇIKÇA istenirse yap

## 4. Iki dropdown, bir kaynak
- "Add" modal'ı ve "Edit" modal'ı genellikle AYNI component
- Birinde davranış değiştirirsen diğerini de düşün
- Dropdown içeriği, filter, sort — her ikisi için aynı olmalı

## 5. docs/CRITICAL_PATHS.md
Her iş başlamadan önce bu dosyayı oku. Orada listelenen davranışları BOZMA.
Kodu değiştirdikten sonra listedeki davranışları manuel zihinsel test et:
- "Bu değişiklik X davranışını bozar mı?"

## 6. Komut bittiğinde rapor
- Ne yaptın (1-2 cümle)
- Ne test ettin
- Kontrol etmediğin yan etki var mı (varsa söyle, sakla)
- Kullanıcı hard refresh gerekli mi

## 7. Dur ve sor
Şu durumlarda KOD YAZMA, önce sor:
- Komut muğlak
- Birden fazla yorumu var
- "En iyi çözüm X" ama komut Y diyor
- Destructive iş (DROP, DELETE, force push, rm -rf)
- Migration geri alınamaz (CREATE TABLE, kolon sil, kolon type değiştir)
