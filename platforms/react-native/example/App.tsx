/**
 * Minimal usage example for @ishant89/atc-parser-kit.
 *
 * Drop this into a React Native app (iOS) that has the package installed
 * (`npm install @ishant89/atc-parser-kit && cd ios && pod install`).
 */
import React, { useState } from 'react';
import { SafeAreaView, TextInput, Button, Text, ScrollView } from 'react-native';
import { parse, type ParserResult } from '@ishant89/atc-parser-kit';

export default function App() {
  const [text, setText] = useState(
    'air canada 125 climb flight level 250 turn left heading 270'
  );
  const [result, setResult] = useState<ParserResult | null>(null);

  const onParse = async () => {
    try {
      setResult(await parse(text));
    } catch (e) {
      console.warn(e);
    }
  };

  return (
    <SafeAreaView style={{ flex: 1, padding: 16 }}>
      <TextInput
        value={text}
        onChangeText={setText}
        style={{ borderWidth: 1, padding: 8, marginBottom: 12 }}
      />
      <Button title="Parse" onPress={onParse} />
      <ScrollView style={{ marginTop: 16 }}>
        {result && (
          <Text selectable>{JSON.stringify(result, null, 2)}</Text>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}
