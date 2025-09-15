const fs = require('fs');
const path = require('path');

// 简单的语法检查函数
function checkArkTSSyntax(filePath) {
  try {
    const content = fs.readFileSync(filePath, 'utf8');
    const lines = content.split('\n');
    const errors = [];
    
    lines.forEach((line, index) => {
      const lineNum = index + 1;
      
      // 检查模板字符串中的命名空间使用
      const templateStringRegex = /`[^`]*\$\{[^}]*\b(router|Color|RecordState|hilog)\b(?!Status)[^}]*\}[^`]*`/g;
      if (templateStringRegex.test(line)) {
        errors.push(`Line ${lineNum}: Potential namespace usage in template string: ${line.trim()}`);
      }
      
      // 检查直接的命名空间对象使用
      const namespaceRegex = /typeof\s+(router|Color|RecordState|hilog)\s*[!=]==/g;
      if (namespaceRegex.test(line)) {
        errors.push(`Line ${lineNum}: Direct namespace object usage: ${line.trim()}`);
      }
    });
    
    return errors;
  } catch (error) {
    return [`Error reading file: ${error.message}`];
  }
}

// 检查RecordPage.ets
const recordPagePath = path.join(__dirname, 'entry/src/main/ets/pages/RecordPage.ets');
const audioServicePath = path.join(__dirname, 'entry/src/main/ets/service/AudioRecorderService.ets');

console.log('Checking RecordPage.ets...');
const recordPageErrors = checkArkTSSyntax(recordPagePath);
if (recordPageErrors.length > 0) {
  console.log('RecordPage.ets errors:');
  recordPageErrors.forEach(error => console.log('  ' + error));
} else {
  console.log('RecordPage.ets: No ArkTS syntax errors found');
}

console.log('\nChecking AudioRecorderService.ets...');
const audioServiceErrors = checkArkTSSyntax(audioServicePath);
if (audioServiceErrors.length > 0) {
  console.log('AudioRecorderService.ets errors:');
  audioServiceErrors.forEach(error => console.log('  ' + error));
} else {
  console.log('AudioRecorderService.ets: No ArkTS syntax errors found');
}

console.log('\nSyntax check completed.');